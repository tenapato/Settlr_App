import Foundation
import Observation

@Observable
final class IncomeVM {
    var incomes: [Income] = []
    var categories: [Category] = []
    var recurring: [RecurringIncome] = []
    var isLoading = false
    var errorMessage: String?

    var searchText = ""
    var filterCategoryId: String?

    var selectedMonth: String = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM"
        return f.string(from: Date())
    }()

    private let api = APIClient.shared
    private var categoryLoadGeneration = 0
    private var categoryWorkspaceID: String?

    var hasActiveFilter: Bool {
        !searchText.isEmpty || filterCategoryId != nil
    }

    var activeRecurringCount: Int {
        recurring.filter(\.active).count
    }

    var filteredIncomes: [Income] {
        let catMap = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0.name) })
        return incomes.filter { item in
            if let catId = filterCategoryId, item.categoryId != catId { return false }
            if !searchText.isEmpty {
                let q = searchText.lowercased()
                var parts: [String] = [item.description, item.source ?? ""]
                if let catName = catMap[item.categoryId ?? ""] { parts.append(catName) }
                let textHit = parts.contains { $0.lowercased().contains(q) }
                let amountHit = matchesAmount(q, cents: item.amountCents)
                if !textHit && !amountHit { return false }
            }
            return true
        }
    }

    func clearFilters() {
        searchText = ""
        filterCategoryId = nil
    }

    @MainActor
    func resetCategoriesForWorkspace(_ workspaceId: String) {
        categoryLoadGeneration += 1
        categoryWorkspaceID = workspaceId
        categories = []
    }

    /// Returns a token Activity can use to reject a save response that crosses
    /// a workspace switch. Existing callers do not need to participate.
    @MainActor
    func workspaceMutationGeneration(for workspaceId: String) -> Int {
        guard categoryWorkspaceID == workspaceId else { return -1 }
        return categoryLoadGeneration
    }

    private func acceptsMutation(
        workspaceId: String,
        expectedGeneration: Int?
    ) -> Bool {
        guard let expectedGeneration else { return true }
        return categoryWorkspaceID == workspaceId && categoryLoadGeneration == expectedGeneration
    }

    @MainActor
    func loadCategories(workspaceId: String) async {
        if categoryWorkspaceID != workspaceId {
            resetCategoriesForWorkspace(workspaceId)
        }
        let generation = categoryLoadGeneration
        do {
            let response: CategoriesResponse = try await api.fetch(
                Endpoints.categories(workspaceId) + "?scope=income"
            )
            guard generation == categoryLoadGeneration, categoryWorkspaceID == workspaceId else { return }
            categories = response.categories
        } catch {
            guard generation == categoryLoadGeneration, categoryWorkspaceID == workspaceId else { return }
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    func load(workspaceId: String) async {
        isLoading = true
        defer { isLoading = false }
        async let incomeTask: IncomeListResponse = api.fetch(
            Endpoints.income(workspaceId) + MonthRangeQuery.ledgerQuery(month: selectedMonth)
        )
        async let catsTask: CategoriesResponse = api.fetch(
            Endpoints.categories(workspaceId) + "?scope=income"
        )
        // Recurring rules are supplementary: the endpoint may be absent on a given
        // deployment, and losing them must not blank out the ledger.
        async let recurringTask: RecurringIncomeListResponse? = try? await api.fetch(
            Endpoints.recurringIncome(workspaceId)
        )
        do {
            let (incResp, catResp) = try await (incomeTask, catsTask)
            incomes = incResp.income
            categories = catResp.categories
        } catch {
            errorMessage = error.localizedDescription
        }
        recurring = await recurringTask?.recurringIncome ?? []
    }

    @MainActor
    func create(
        workspaceId: String,
        body: CreateIncomeBody,
        expectedGeneration: Int? = nil
    ) async {
        do {
            let response: CreateIncomeResponse = try await api.fetch(
                Endpoints.income(workspaceId),
                method: "POST",
                body: body
            )
            guard acceptsMutation(workspaceId: workspaceId, expectedGeneration: expectedGeneration) else { return }
            incomes.insert(response.income, at: 0)
        } catch {
            guard acceptsMutation(workspaceId: workspaceId, expectedGeneration: expectedGeneration) else { return }
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    @discardableResult
    func update(
        workspaceId: String,
        incomeId: String,
        body: CreateIncomeBody,
        expectedGeneration: Int? = nil
    ) async -> Income? {
        do {
            let response: CreateIncomeResponse = try await api.fetch(
                Endpoints.incomeItem(workspaceId, incomeId),
                method: "PATCH",
                body: body
            )
            guard acceptsMutation(workspaceId: workspaceId, expectedGeneration: expectedGeneration) else { return nil }
            if let idx = incomes.firstIndex(where: { $0.id == incomeId }) {
                incomes[idx] = response.income
            }
            return response.income
        } catch {
            guard acceptsMutation(workspaceId: workspaceId, expectedGeneration: expectedGeneration) else { return nil }
            errorMessage = error.localizedDescription
            return nil
        }
    }

    @MainActor
    func delete(
        workspaceId: String,
        incomeId: String,
        expectedGeneration: Int? = nil
    ) async {
        do {
            try await api.send(Endpoints.incomeItem(workspaceId, incomeId), method: "DELETE")
            guard acceptsMutation(workspaceId: workspaceId, expectedGeneration: expectedGeneration) else { return }
            incomes.removeAll { $0.id == incomeId }
        } catch {
            guard acceptsMutation(workspaceId: workspaceId, expectedGeneration: expectedGeneration) else { return }
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Recurring income rules

    @MainActor
    func createRecurring(
        workspaceId: String,
        body: CreateRecurringIncomeBody,
        reload: Bool = true,
        expectedGeneration: Int? = nil
    ) async -> Bool {
        do {
            let _: RecurringIncomeResponse = try await api.fetch(
                Endpoints.recurringIncome(workspaceId),
                method: "POST",
                body: body
            )
            guard acceptsMutation(workspaceId: workspaceId, expectedGeneration: expectedGeneration) else { return false }
            if reload { await load(workspaceId: workspaceId) }
            return true
        } catch {
            guard acceptsMutation(workspaceId: workspaceId, expectedGeneration: expectedGeneration) else { return false }
            errorMessage = error.localizedDescription
            return false
        }
    }

    @MainActor
    func updateRecurring(
        workspaceId: String,
        ruleId: String,
        body: UpdateRecurringIncomeBody
    ) async -> Bool {
        do {
            let _: RecurringIncomeResponse = try await api.fetch(
                Endpoints.recurringIncomeRule(workspaceId, ruleId),
                method: "PATCH",
                body: body
            )
            await load(workspaceId: workspaceId)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    @MainActor
    func deleteRecurring(workspaceId: String, ruleId: String) async {
        do {
            try await api.send(
                Endpoints.recurringIncomeRule(workspaceId, ruleId),
                method: "DELETE"
            )
            await load(workspaceId: workspaceId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func matchesAmount(_ q: String, cents: Int) -> Bool {
        let stripped = q.replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespaces)
        guard let val = Double(stripped) else { return false }
        let amount = Double(cents) / 100.0
        return abs(amount - val) < 0.01 || abs(amount - val * 100) < 0.01
    }
}

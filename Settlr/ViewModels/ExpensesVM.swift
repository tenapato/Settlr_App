import Foundation
import Observation

@Observable
final class ExpensesVM {
    var expenses: [Expense] = []
    var categories: [Category] = []
    var cards: [CreditCard] = []
    var isLoading = false
    var errorMessage: String?

    var searchText = ""
    var filterChannel: String?
    var filterCategoryId: String?
    var filterCardId: String?

    var selectedMonth: String = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM"
        return f.string(from: Date())
    }()

    private let api = APIClient.shared
    private var categoryLoadGeneration = 0
    private var categoryWorkspaceID: String?

    var hasActiveFilter: Bool {
        !searchText.isEmpty || filterChannel != nil || filterCategoryId != nil || filterCardId != nil
    }

    var filteredExpenses: [Expense] {
        let catMap = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0.name) })
        let cardMap = Dictionary(uniqueKeysWithValues: cards.map { ($0.id, $0) })
        return expenses.filter { e in
            if let ch = filterChannel, e.paymentChannel != ch { return false }
            if let cid = filterCardId, e.creditCardId != cid { return false }
            if let catId = filterCategoryId, e.categoryId != catId { return false }
            if !searchText.isEmpty {
                let q = searchText.lowercased()
                var parts: [String] = [e.description, e.notes ?? ""]
                if let catName = catMap[e.categoryId ?? ""] { parts.append(catName) }
                parts.append(e.paymentChannel == "cash" ? "cash" : "card")
                if let cardId = e.creditCardId, let card = cardMap[cardId] {
                    parts.append(card.label)
                    if let lf = card.lastFour { parts.append(lf) }
                }
                let textHit = parts.contains { $0.lowercased().contains(q) }
                let amountHit = matchesAmount(q, cents: e.amountCents)
                if !textHit && !amountHit { return false }
            }
            return true
        }
    }

    func clearFilters() {
        searchText = ""
        filterChannel = nil
        filterCategoryId = nil
        filterCardId = nil
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
                Endpoints.categories(workspaceId) + "?scope=expense"
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
        async let expTask: ExpensesResponse = api.fetch(
            Endpoints.expenses(workspaceId) + MonthRangeQuery.ledgerQuery(month: selectedMonth)
        )
        async let catTask: CategoriesResponse = api.fetch(
            Endpoints.categories(workspaceId) + "?scope=expense"
        )
        async let cardTask: CreditCardsResponse = api.fetch(
            Endpoints.creditCards(workspaceId)
        )
        do {
            let (expResp, catResp, cardResp) = try await (expTask, catTask, cardTask)
            expenses = expResp.expenses
            categories = catResp.categories
            cards = cardResp.creditCards
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    func create(
        workspaceId: String,
        body: CreateExpenseBody,
        expectedGeneration: Int? = nil
    ) async {
        do {
            let response: CreateExpenseResponse = try await api.fetch(
                Endpoints.expenses(workspaceId),
                method: "POST",
                body: body
            )
            guard acceptsMutation(workspaceId: workspaceId, expectedGeneration: expectedGeneration) else { return }
            expenses.insert(response.expense, at: 0)
        } catch {
            guard acceptsMutation(workspaceId: workspaceId, expectedGeneration: expectedGeneration) else { return }
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    @discardableResult
    func update(
        workspaceId: String,
        expenseId: String,
        body: CreateExpenseBody,
        expectedGeneration: Int? = nil
    ) async -> Expense? {
        do {
            let response: CreateExpenseResponse = try await api.fetch(
                Endpoints.expense(workspaceId, expenseId),
                method: "PATCH",
                body: body
            )
            guard acceptsMutation(workspaceId: workspaceId, expectedGeneration: expectedGeneration) else { return nil }
            if let idx = expenses.firstIndex(where: { $0.id == expenseId }) {
                expenses[idx] = response.expense
            }
            return response.expense
        } catch {
            guard acceptsMutation(workspaceId: workspaceId, expectedGeneration: expectedGeneration) else { return nil }
            errorMessage = error.localizedDescription
            return nil
        }
    }

    @MainActor
    func delete(
        workspaceId: String,
        expenseId: String,
        expectedGeneration: Int? = nil
    ) async {
        do {
            try await api.send(Endpoints.expense(workspaceId, expenseId), method: "DELETE")
            guard acceptsMutation(workspaceId: workspaceId, expectedGeneration: expectedGeneration) else { return }
            expenses.removeAll { $0.id == expenseId }
        } catch {
            guard acceptsMutation(workspaceId: workspaceId, expectedGeneration: expectedGeneration) else { return }
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

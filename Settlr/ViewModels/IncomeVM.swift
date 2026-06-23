import Foundation
import Observation

@Observable
final class IncomeVM {
    var incomes: [Income] = []
    var categories: [Category] = []
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

    var hasActiveFilter: Bool {
        !searchText.isEmpty || filterCategoryId != nil
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
    func load(workspaceId: String) async {
        isLoading = true
        defer { isLoading = false }
        async let incomeTask: IncomeListResponse = api.fetch(
            Endpoints.income(workspaceId) + MonthRangeQuery.ledgerQuery(month: selectedMonth)
        )
        async let catsTask: CategoriesResponse = api.fetch(
            Endpoints.categories(workspaceId) + "?scope=income"
        )
        do {
            let (incResp, catResp) = try await (incomeTask, catsTask)
            incomes = incResp.income
            categories = catResp.categories
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    func create(workspaceId: String, body: CreateIncomeBody) async {
        do {
            let response: CreateIncomeResponse = try await api.fetch(
                Endpoints.income(workspaceId),
                method: "POST",
                body: body
            )
            incomes.insert(response.income, at: 0)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    @discardableResult
    func update(workspaceId: String, incomeId: String, body: CreateIncomeBody) async -> Income? {
        do {
            let response: CreateIncomeResponse = try await api.fetch(
                Endpoints.incomeItem(workspaceId, incomeId),
                method: "PATCH",
                body: body
            )
            if let idx = incomes.firstIndex(where: { $0.id == incomeId }) {
                incomes[idx] = response.income
            }
            return response.income
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    @MainActor
    func delete(workspaceId: String, incomeId: String) async {
        do {
            try await api.send(Endpoints.incomeItem(workspaceId, incomeId), method: "DELETE")
            incomes.removeAll { $0.id == incomeId }
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

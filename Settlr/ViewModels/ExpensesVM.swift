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
    func load(workspaceId: String) async {
        isLoading = true
        defer { isLoading = false }
        async let expTask: ExpensesResponse = api.fetch(
            Endpoints.expenses(workspaceId) + monthQuery()
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
    func create(workspaceId: String, body: CreateExpenseBody) async {
        do {
            let response: CreateExpenseResponse = try await api.fetch(
                Endpoints.expenses(workspaceId),
                method: "POST",
                body: body
            )
            expenses.insert(response.expense, at: 0)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    func delete(workspaceId: String, expenseId: String) async {
        do {
            try await api.send(Endpoints.expense(workspaceId, expenseId), method: "DELETE")
            expenses.removeAll { $0.id == expenseId }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func monthQuery() -> String {
        let parts = selectedMonth.split(separator: "-")
        guard parts.count == 2,
              let year = Int(parts[0]),
              let month = Int(parts[1]) else { return "" }
        let from = String(format: "%04d-%02d-01", year, month)
        let lastDay = lastDayOfMonth(year: year, month: month)
        let to = String(format: "%04d-%02d-%02d", year, month, lastDay)
        return "?from=\(from)&to=\(to)"
    }

    private func lastDayOfMonth(year: Int, month: Int) -> Int {
        var comps = DateComponents()
        comps.year = year; comps.month = month + 1; comps.day = 0
        return Calendar.current.date(from: comps).map {
            Calendar.current.component(.day, from: $0)
        } ?? 30
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

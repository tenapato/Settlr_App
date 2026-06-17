import Foundation

struct SummaryResponse: Decodable {
    let incomeCents: Int
    let expenseCents: Int
    let netCents: Int
    let expensesByCategory: [CategorySummary]

    var income: Double { Double(incomeCents) / 100.0 }
    var expenses: Double { Double(expenseCents) / 100.0 }
    var net: Double { Double(netCents) / 100.0 }
}

struct CategorySummary: Decodable, Identifiable {
    let categoryId: String?
    let categoryName: String?
    let totalCents: Int

    var id: String { categoryId ?? "uncategorized" }
    var total: Double { Double(totalCents) / 100.0 }
}

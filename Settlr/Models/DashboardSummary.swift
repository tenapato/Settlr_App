import Foundation

struct ExpensesByChannel: Decodable {
    let cashCents: Int
    let creditCardCents: Int
}

struct SummaryResponse: Decodable {
    let incomeCents: Int
    let expenseCents: Int
    let netCents: Int
    let incomeCount: Int
    let expenseCount: Int
    let transactionCount: Int
    let expensesByCategory: [CategorySummary]
    let expensesByChannel: ExpensesByChannel

    var income: Double { Double(incomeCents) / 100.0 }
    var expenses: Double { Double(expenseCents) / 100.0 }
    var net: Double { Double(netCents) / 100.0 }

    /// The API does not sort `expensesByCategory`; always read through this.
    var sortedCategories: [CategorySummary] {
        expensesByCategory.sorted { $0.totalCents > $1.totalCents }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        incomeCents = try container.decodeIfPresent(Int.self, forKey: .incomeCents) ?? 0
        expenseCents = try container.decodeIfPresent(Int.self, forKey: .expenseCents) ?? 0
        netCents = try container.decodeIfPresent(Int.self, forKey: .netCents) ?? 0
        incomeCount = try container.decodeIfPresent(Int.self, forKey: .incomeCount) ?? 0
        expenseCount = try container.decodeIfPresent(Int.self, forKey: .expenseCount) ?? 0
        let total = try container.decodeIfPresent(Int.self, forKey: .transactionCount)
        transactionCount = total ?? (incomeCount + expenseCount)
        expensesByCategory = try container.decodeIfPresent([CategorySummary].self, forKey: .expensesByCategory) ?? []
        expensesByChannel = try container.decodeIfPresent(ExpensesByChannel.self, forKey: .expensesByChannel)
            ?? ExpensesByChannel(cashCents: 0, creditCardCents: expenseCents)
    }

    private enum CodingKeys: String, CodingKey {
        case incomeCents, expenseCents, netCents
        case incomeCount, expenseCount, transactionCount
        case expensesByCategory, expensesByChannel
    }
}

struct CategorySummary: Decodable, Identifiable {
    let categoryId: String?
    let categoryName: String?
    let totalCents: Int

    var id: String { categoryId ?? "uncategorized" }
    var total: Double { Double(totalCents) / 100.0 }
}

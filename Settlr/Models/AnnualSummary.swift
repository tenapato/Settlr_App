import Foundation

struct MonthDataPoint: Decodable, Identifiable {
    let month: String
    let incomeCents: Int
    let expenseCents: Int
    let netCents: Int
    var id: String { month }
}

struct AnnualSummaryResponse: Decodable {
    let year: Int
    let months: [MonthDataPoint]
}

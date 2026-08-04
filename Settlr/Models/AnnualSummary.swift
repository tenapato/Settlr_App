import Foundation

struct MonthDataPoint: Decodable, Identifiable {
    let month: String
    let incomeCents: Int
    let expenseCents: Int
    let netCents: Int
    let savingsNetCents: Int
    var id: String { month }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        month = try c.decode(String.self, forKey: .month)
        incomeCents = try c.decodeIfPresent(Int.self, forKey: .incomeCents) ?? 0
        expenseCents = try c.decodeIfPresent(Int.self, forKey: .expenseCents) ?? 0
        netCents = try c.decodeIfPresent(Int.self, forKey: .netCents) ?? 0
        savingsNetCents = try c.decodeIfPresent(Int.self, forKey: .savingsNetCents) ?? 0
    }

    private enum CodingKeys: String, CodingKey {
        case month, incomeCents, expenseCents, netCents, savingsNetCents
    }
}

struct AnnualSummaryResponse: Decodable {
    let year: Int
    let months: [MonthDataPoint]
}

import Foundation

struct Income: Codable, Identifiable {
    let id: String
    let description: String
    let amountCents: Int
    let currency: String
    let occurredAt: String
    let categoryId: String?
    let source: String?
    let recurringSeriesId: String?

    var amount: Double { Double(amountCents) / 100.0 }

    var displayDate: String { formatIncomeDate(occurredAt) }
    var isRecurring: Bool { recurringSeriesId != nil && !(recurringSeriesId?.isEmpty ?? true) }
}

private func formatIncomeDate(_ raw: String) -> String {
    let formats = ["yyyy-MM-dd'T'HH:mm:ss.SSSZ", "yyyy-MM-dd'T'HH:mm:ssZ", "yyyy-MM-dd"]
    let out = DateFormatter()
    out.dateStyle = .medium
    out.timeStyle = .none
    for fmt in formats {
        let f = DateFormatter()
        f.dateFormat = fmt
        if let d = f.date(from: raw) { return out.string(from: d) }
    }
    return String(raw.prefix(10))
}

struct IncomeListResponse: Decodable {
    let income: [Income]
}

struct CreateIncomeBody: Encodable {
    let description: String
    let amountCents: Int
    let occurredAt: String
    let categoryId: String?
    let currency: String = "MXN"
}

struct CreateIncomeResponse: Decodable {
    let income: Income
}

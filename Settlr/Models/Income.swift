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

// MARK: - Recurring income

/// A monthly income rule. Rows are materialized into the ledger as each month is viewed.
struct RecurringIncome: Codable, Identifiable, Hashable {
    let id: String
    let amountCents: Int
    let currency: String
    let description: String
    let categoryId: String?
    let source: String?
    let startDate: String
    let frequency: String
    let dayOfMonth: Int
    let active: Bool

    var amount: Double { Double(amountCents) / 100.0 }
    var cadence: RecurrenceFrequency { RecurrenceFrequency(rawValue: frequency) ?? .monthly }

    enum CodingKeys: String, CodingKey {
        case id, amountCents, currency, description, categoryId, source, startDate, dayOfMonth, active
        case frequency
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        amountCents = try c.decode(Int.self, forKey: .amountCents)
        currency = try c.decode(String.self, forKey: .currency)
        description = try c.decode(String.self, forKey: .description)
        categoryId = try c.decodeIfPresent(String.self, forKey: .categoryId)
        source = try c.decodeIfPresent(String.self, forKey: .source)
        dayOfMonth = try c.decode(Int.self, forKey: .dayOfMonth)
        // Older servers predate cadences; those rules are monthly.
        frequency = (try? c.decode(String.self, forKey: .frequency)) ?? "monthly"
        active = (try? c.decode(Bool.self, forKey: .active)) ?? true
        if let s = try? c.decode(String.self, forKey: .startDate) {
            startDate = s
        } else if let i = try? c.decode(Int.self, forKey: .startDate) {
            startDate = String(i)
        } else if let d = try? c.decode(Double.self, forKey: .startDate) {
            startDate = String(Int(d))
        } else {
            throw DecodingError.dataCorruptedError(
                forKey: .startDate,
                in: c,
                debugDescription: "startDate must be string or number"
            )
        }
    }
}

struct RecurringIncomeListResponse: Decodable {
    let recurringIncome: [RecurringIncome]
}

struct RecurringIncomeResponse: Decodable {
    let recurringIncome: RecurringIncome
}

struct CreateRecurringIncomeBody: Encodable {
    let amountCents: Int
    let description: String
    let frequency: String
    let startDate: String
    let categoryId: String?
    let currency: String = "MXN"
}

struct UpdateRecurringIncomeBody: Encodable {
    let amountCents: Int?
    let description: String?
    let frequency: String?
    let startDate: String?
    let categoryId: String?
    let active: Bool?

    init(
        amountCents: Int? = nil,
        description: String? = nil,
        frequency: String? = nil,
        startDate: String? = nil,
        categoryId: String? = nil,
        active: Bool? = nil
    ) {
        self.amountCents = amountCents
        self.description = description
        self.frequency = frequency
        self.startDate = startDate
        self.categoryId = categoryId
        self.active = active
    }
}

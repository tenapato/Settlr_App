import Foundation

func savingsTargetAmountText(for targetAmountCents: Int?) -> String {
    guard let targetAmountCents else { return "" }
    return String(format: "%.2f", Double(targetAmountCents) / 100.0)
}

enum SavingsTargetAmountError: Error, Equatable {
    case invalid
}

/// Parses the optional account goal amount without allowing malformed or
/// overflowing values to reach an Int conversion.
func parseSavingsTargetAmount(_ raw: String) throws -> Int? {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    guard let amount = Double(trimmed), amount.isFinite, amount > 0 else {
        throw SavingsTargetAmountError.invalid
    }
    let cents = amount * 100
    guard cents.isFinite, cents.rounded() > 0, cents.rounded() < Double(Int.max) else {
        throw SavingsTargetAmountError.invalid
    }
    return Int(cents.rounded())
}

struct SavingsAccount: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let currency: String
    let color: String?
    let sortOrder: Int
    let balanceCents: Int
    /// Optional goal metadata is supplied by the Server goal-target rollout.
    /// Missing fields intentionally preserve flexible accounts from older responses.
    let targetAmountCents: Int?
    let targetDate: String?
    let goalStatus: String?
    let progressPct: Double?
    let remainingCents: Int?

    var amount: Double { Double(balanceCents) / 100.0 }
}

struct SavingsEntry: Codable, Identifiable, Hashable {
    let id: String
    let accountId: String
    let direction: String
    let amountCents: Int
    let currency: String
    let occurredAt: String
    let description: String
    let notes: String?
    let recurringSeriesId: String?

    var isDeposit: Bool { direction == "deposit" }
    var amount: Double { Double(amountCents) / 100.0 }
    var displayDate: String { formatSavingsDate(occurredAt) }
    var isRecurring: Bool { !(recurringSeriesId ?? "").isEmpty }

    enum CodingKeys: String, CodingKey {
        case id, accountId, direction, amountCents, currency, occurredAt, description, notes
        case recurringSeriesId
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        accountId = try c.decode(String.self, forKey: .accountId)
        direction = try c.decode(String.self, forKey: .direction)
        amountCents = try c.decode(Int.self, forKey: .amountCents)
        currency = try c.decode(String.self, forKey: .currency)
        description = try c.decode(String.self, forKey: .description)
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
        recurringSeriesId = try c.decodeIfPresent(String.self, forKey: .recurringSeriesId)
        guard let occurred = decodeLooseDateString(c, forKey: .occurredAt) else {
            throw DecodingError.dataCorruptedError(
                forKey: .occurredAt,
                in: c,
                debugDescription: "occurredAt must be string or number"
            )
        }
        occurredAt = occurred
    }
}

/// A recurring investment: an automatic deposit into one savings account.
struct RecurringSavings: Codable, Identifiable, Hashable {
    let id: String
    let accountId: String
    let amountCents: Int
    let currency: String
    let description: String
    let notes: String?
    let frequency: String
    let startDate: String
    let active: Bool

    var amount: Double { Double(amountCents) / 100.0 }
    var cadence: RecurrenceFrequency { RecurrenceFrequency(rawValue: frequency) ?? .monthly }
    var displayStartDate: String { formatSavingsDate(startDate) }

    enum CodingKeys: String, CodingKey {
        case id, accountId, amountCents, currency, description, notes, frequency, startDate, active
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        accountId = try c.decode(String.self, forKey: .accountId)
        amountCents = try c.decode(Int.self, forKey: .amountCents)
        currency = try c.decode(String.self, forKey: .currency)
        description = try c.decode(String.self, forKey: .description)
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
        frequency = try c.decode(String.self, forKey: .frequency)
        active = (try? c.decode(Bool.self, forKey: .active)) ?? true
        guard let start = decodeLooseDateString(c, forKey: .startDate) else {
            throw DecodingError.dataCorruptedError(
                forKey: .startDate,
                in: c,
                debugDescription: "startDate must be string or number"
            )
        }
        startDate = start
    }
}

/// Timestamps arrive as ISO strings, but tolerate epoch numbers from older payloads.
private func decodeLooseDateString<K: CodingKey>(
    _ container: KeyedDecodingContainer<K>,
    forKey key: K
) -> String? {
    if let s = try? container.decode(String.self, forKey: key) { return s }
    if let i = try? container.decode(Int.self, forKey: key) { return String(i) }
    if let d = try? container.decode(Double.self, forKey: key) { return String(Int(d)) }
    return nil
}

private func formatSavingsDate(_ raw: String) -> String {
    let formats = ["yyyy-MM-dd'T'HH:mm:ss.SSSZ", "yyyy-MM-dd'T'HH:mm:ssZ", "yyyy-MM-dd"]
    let out = DateFormatter()
    out.dateStyle = .medium
    out.timeStyle = .none
    for fmt in formats {
        let f = DateFormatter()
        f.dateFormat = fmt
        if let d = f.date(from: raw) { return out.string(from: d) }
    }
    // Epoch ms as string
    if let ms = Double(raw), ms > 1_000_000_000_000 {
        return out.string(from: Date(timeIntervalSince1970: ms / 1000))
    }
    return String(raw.prefix(10))
}

// MARK: - Responses

struct SavingsAccountsResponse: Decodable {
    let accounts: [SavingsAccount]
    let totalBalanceCents: Int
}

struct SavingsAccountResponse: Decodable {
    let account: SavingsAccount
}

struct SavingsEntriesResponse: Decodable {
    let entries: [SavingsEntry]
}

struct SavingsEntryResponse: Decodable {
    let entry: SavingsEntry
    let balanceCents: Int?
}

// MARK: - Request bodies

struct CreateSavingsAccountBody: Encodable {
    let name: String
    let color: String?
    let currency: String
    let targetAmountCents: Int?
    let targetDate: String?

    init(
        name: String,
        color: String?,
        currency: String,
        targetAmountCents: Int? = nil,
        targetDate: String? = nil
    ) {
        self.name = name
        self.color = color
        self.currency = currency
        self.targetAmountCents = targetAmountCents
        self.targetDate = targetDate
    }
}

struct UpdateSavingsAccountBody: Encodable {
    let name: String
    let color: String?
    let targetAmountCents: Int?
    let targetDate: String?

    init(
        name: String,
        color: String?,
        targetAmountCents: Int? = nil,
        targetDate: String? = nil
    ) {
        self.name = name
        self.color = color
        self.targetAmountCents = targetAmountCents
        self.targetDate = targetDate
    }

    /// PATCH must send explicit nulls when a user clears a goal. Without this
    /// custom encoding, synthesized Codable omits nil and leaves old targets set.
    enum CodingKeys: String, CodingKey {
        case name, color, targetAmountCents, targetDate
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(color, forKey: .color)
        try container.encode(targetAmountCents, forKey: .targetAmountCents)
        try container.encode(targetDate, forKey: .targetDate)
    }
}

struct CreateSavingsEntryBody: Encodable {
    let accountId: String
    let direction: String
    let amountCents: Int
    let description: String
    let occurredAt: String
    let notes: String?
    let currency: String = "MXN"
}

struct RecurringSavingsListResponse: Decodable {
    let recurringSavings: [RecurringSavings]
}

struct RecurringSavingsResponse: Decodable {
    let recurringSavings: RecurringSavings
}

struct CreateRecurringSavingsBody: Encodable {
    let accountId: String
    let amountCents: Int
    let description: String
    let frequency: String
    let startDate: String
    let notes: String?
    let currency: String = "MXN"
}

struct UpdateRecurringSavingsBody: Encodable {
    let accountId: String?
    let amountCents: Int?
    let description: String?
    let frequency: String?
    let startDate: String?
    let notes: String?
    let active: Bool?

    init(
        accountId: String? = nil,
        amountCents: Int? = nil,
        description: String? = nil,
        frequency: String? = nil,
        startDate: String? = nil,
        notes: String? = nil,
        active: Bool? = nil
    ) {
        self.accountId = accountId
        self.amountCents = amountCents
        self.description = description
        self.frequency = frequency
        self.startDate = startDate
        self.notes = notes
        self.active = active
    }
}

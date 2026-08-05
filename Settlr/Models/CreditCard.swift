import Foundation

struct CreditCard: Codable, Identifiable {
    let id: String
    let label: String
    let lastFour: String?
    let network: String?
    let issuer: String?
    let creditLimitCents: Int?
    let statementCutoffDay: Int?
    let paymentDueDay: Int?
    let notes: String?
    /// Set when the card was deactivated. The list endpoint still returns those
    /// rows so history keeps rendering; pickers for new charges filter them out.
    /// Defaults to nil so locally-built preview cards stay easy to construct.
    var archivedAt: String? = nil

    var isArchived: Bool { archivedAt != nil }
}

struct CreditCardsResponse: Decodable {
    let creditCards: [CreditCard]
}

struct CreateCreditCardBody: Encodable {
    let label: String
    let lastFour: String?
    let network: String?
    let creditLimitCents: Int?
}

struct UpdateCreditCardBody: Encodable {
    let label: String
    let lastFour: String?
    let network: String?
    let issuer: String?
    let creditLimitCents: Int?
    let statementCutoffDay: Int?
    let paymentDueDay: Int?
    let notes: String?
}

struct CreditCardResponse: Decodable {
    let creditCard: CreditCard
}

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

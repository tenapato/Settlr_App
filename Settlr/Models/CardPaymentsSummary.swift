import Foundation

/// Subset of the server's CardPaymentsSummaryResponse that the Payments screen renders.
/// Extra JSON keys (activity, payments, topExpenses, ...) are ignored by Codable.
struct CardPaymentRow: Decodable, Identifiable {
    let creditCardId: String
    let label: String
    let lastFour: String?
    let creditLimitCents: Int?
    let statementCutoffDay: Int?
    let paymentDueDay: Int?
    let spentCents: Int
    let utilizationPct: Double?
    let utilizationStatus: String // "no_limit" | "ok" | "warning" | "over_limit"
    let paymentDueCents: Int
    let dueSource: String // "spent" | "override"
    let paidInFull: Bool
    let paymentsRecordedCents: Int

    var id: String { creditCardId }
    var outstandingCents: Int { max(0, paymentDueCents - paymentsRecordedCents) }
}

struct CardPaymentsTotals: Decodable {
    let totalPaymentDueCents: Int
    let totalPaymentsRecordedCents: Int
    let remainingDueCents: Int
    let afterCardPaymentsCents: Int
}

struct CardPaymentsSummaryResponse: Decodable {
    let creditCards: [CardPaymentRow]
    let totals: CardPaymentsTotals
}

struct MarkCardPaidBody: Encodable {
    let month: String
}

struct MarkCardPaidResponse: Decodable {
    let ok: Bool
    let month: String
    let creditCardId: String
    let paidInFull: Bool
}

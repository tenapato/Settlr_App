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

/// The append-only payment record accepted by the monthly card-payment route.
/// The server remains authoritative for statement balance and paid status.
struct MonthlyCardPaymentBody: Encodable, Equatable {
    let month: String
    let creditCardId: String
    let amountCents: Int
    let note: String?
    let paidAt: String
}

/// Foundation-only preparation for the record-payment sheet. Keeping this
/// boundary outside SwiftUI makes the wire data testable without Xcode.
enum CardPaymentDraft {
    static func makeBody(
        month: String,
        cardId: String,
        amountText: String,
        note: String,
        paidAt: Date
    ) -> MonthlyCardPaymentBody? {
        guard let amountCents = amountCents(from: amountText), amountCents > 0 else { return nil }
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return MonthlyCardPaymentBody(
            month: month,
            creditCardId: cardId,
            amountCents: amountCents,
            note: trimmedNote.isEmpty ? nil : trimmedNote,
            paidAt: dateString(from: paidAt)
        )
    }

    /// Accepts both `1,234.50` and `1.234,50`, while retaining the existing
    /// simple comma-decimal entry behavior used by the app's amount fields.
    static func amountCents(from text: String) -> Int? {
        let input = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: " ", with: "")
        guard !input.isEmpty, !input.contains("-") else { return nil }

        let separators = input.indices.filter { input[$0] == "." || input[$0] == "," }
        let lastSeparator = separators.last
        let fraction: String
        let wholeText: String

        if let lastSeparator {
            let suffix = String(input[input.index(after: lastSeparator)...])
            if (1...2).contains(suffix.count) {
                fraction = suffix
                wholeText = String(input[..<lastSeparator])
            } else {
                fraction = ""
                wholeText = input
            }
        } else {
            fraction = ""
            wholeText = input
        }

        let wholeDigits = wholeText.filter(\.isNumber)
        guard !wholeDigits.isEmpty,
              wholeText.allSatisfy({ $0.isNumber || $0 == "." || $0 == "," }),
              fraction.allSatisfy(\.isNumber),
              let whole = Int(wholeDigits) else { return nil }

        let fractionDigits = String((fraction + "00").prefix(2))
        guard let cents = Int(fractionDigits) else { return nil }
        let result = whole.multipliedReportingOverflow(by: 100)
        guard !result.overflow else { return nil }
        let total = result.partialValue.addingReportingOverflow(cents)
        return total.overflow ? nil : total.partialValue
    }

    static func formattedAmount(cents: Int) -> String {
        String(format: "%.2f", Double(cents) / 100)
    }

    static func dateString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

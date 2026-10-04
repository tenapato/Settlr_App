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

/// Selection context captured when a card-payment summary request starts.
/// A response must never be committed after the user changes either filter.
struct CardPaymentLoadSnapshot: Equatable {
    let month: String
    let fortnight: String

    func matches(month: String, fortnight: String) -> Bool {
        self.month == month && self.fortnight == fortnight
    }
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

    /// Accepts both `1,234.50` and `1.234,50`, including `.50`, while
    /// rejecting ambiguous repeated separators before a request is sent.
    static func amountCents(from text: String) -> Int? {
        let input = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: " ", with: "")
        guard !input.isEmpty,
              input.allSatisfy({ $0.isNumber || $0 == "." || $0 == "," }) else { return nil }

        let separators = input.indices.filter { input[$0] == "." || input[$0] == "," }
        guard let lastSeparator = separators.last else {
            return cents(wholeDigits: input, fraction: "")
        }

        let fraction = String(input[input.index(after: lastSeparator)...])
        guard !fraction.isEmpty, fraction.allSatisfy(\.isNumber) else { return nil }
        let wholeText = String(input[..<lastSeparator])

        if (1...2).contains(fraction.count) {
            let wholeDigits: String
            if wholeText.isEmpty {
                wholeDigits = "0"
            } else {
                guard let normalized = groupedWholeDigits(wholeText) else { return nil }
                wholeDigits = normalized
            }
            return cents(wholeDigits: wholeDigits, fraction: fraction)
        }

        guard fraction.count == 3,
              let wholeDigits = groupedWholeDigits(input) else { return nil }
        return cents(wholeDigits: wholeDigits, fraction: "")
    }

    private static func groupedWholeDigits(_ text: String) -> String? {
        let separators = Set(text.filter { $0 == "." || $0 == "," })
        guard separators.count <= 1 else { return nil }
        guard let separator = separators.first else {
            return text.allSatisfy(\.isNumber) ? text : nil
        }

        let groups = text.split(separator: separator, omittingEmptySubsequences: false)
        guard groups.count > 1,
              let first = groups.first,
              (1...3).contains(first.count),
              first.allSatisfy(\.isNumber),
              groups.dropFirst().allSatisfy({ $0.count == 3 && $0.allSatisfy(\.isNumber) }) else {
            return nil
        }
        return groups.joined()
    }

    private static func cents(wholeDigits: String, fraction: String) -> Int? {
        guard let whole = Int(wholeDigits) else { return nil }
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

/// A presentation-scoped token. A save may update or dismiss only while the
/// token it started with remains current; replacing a sheet or revoking access
/// invalidates every older token.
struct CardPaymentSaveLifecycle {
    private var generation: UInt64 = 0

    mutating func beginPresentation() -> UInt64 {
        generation &+= 1
        return generation
    }

    mutating func invalidate() {
        generation &+= 1
    }

    func owns(_ token: UInt64) -> Bool {
        generation == token
    }
}

enum CardPaymentRecordResult: Equatable {
    case refreshed
    case recordPaymentRefreshFailed(String)
    case stale
}

enum CardPaymentRecordAction: Equatable {
    case record
    case refresh
}

enum CardPaymentRecordRecoveryResult: Equatable {
    case dismiss
    case showRefreshError(String)
    case ignore
}

/// Once the POST succeeds, the only legal retry is a summary refresh. This
/// prevents a failed refresh from turning the primary button into a duplicate
/// append-only payment request.
struct CardPaymentRecordRecovery {
    private(set) var paymentWasRecorded = false

    var nextAction: CardPaymentRecordAction {
        paymentWasRecorded ? .refresh : .record
    }

    mutating func receive(
        _ result: CardPaymentRecordResult,
        isPresentationCurrent: Bool
    ) -> CardPaymentRecordRecoveryResult {
        guard isPresentationCurrent else { return .ignore }
        switch result {
        case .refreshed:
            return .dismiss
        case .recordPaymentRefreshFailed(let message):
            paymentWasRecorded = true
            return .showRefreshError(message)
        case .stale:
            return .ignore
        }
    }
}

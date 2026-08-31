import Foundation

@main
enum CardPaymentDraftRegression {
    static func main() {
        let paidAt = date("2026-09-18")
        let body = CardPaymentDraft.makeBody(
            month: "2026-08",
            cardId: "card_42",
            amountText: " 1,234.50 ",
            note: "  Groceries  ",
            paidAt: paidAt
        )

        expect(body?.month == "2026-08", "uses the resolved statement month")
        expect(body?.creditCardId == "card_42", "uses the card identifier")
        expect(body?.amountCents == 123_450, "parses grouped decimal currency into cents")
        expect(body?.note == "Groceries", "trims an optional note")
        expect(body?.paidAt == "2026-09-18", "sends the native payment date as an ISO date")

        expect(
            CardPaymentDraft.makeBody(
                month: "2026-08",
                cardId: "card_42",
                amountText: "0",
                note: "   ",
                paidAt: paidAt
            ) == nil,
            "rejects a non-positive amount before sending"
        )
        expect(
            CardPaymentDraft.amountCents(from: "420,75") == 42_075,
            "accepts comma-decimal entry"
        )
        let noNote = CardPaymentDraft.makeBody(
            month: "2026-08",
            cardId: "card_42",
            amountText: "420,75",
            note: "   ",
            paidAt: paidAt
        )
        expect(noNote?.note == nil, "omits a blank optional note")
        expect(CardPaymentDraft.amountCents(from: ".50") == 50, "accepts a fractional amount without a leading zero")
        expect(CardPaymentDraft.amountCents(from: "1..20") == nil, "rejects repeated decimal separators")
        expect(CardPaymentDraft.amountCents(from: "1,23,4") == nil, "rejects malformed grouped separators")

        var lifecycle = CardPaymentSaveLifecycle()
        let firstPresentation = lifecycle.beginPresentation()
        expect(lifecycle.owns(firstPresentation), "owns the active presentation")
        let secondPresentation = lifecycle.beginPresentation()
        expect(!lifecycle.owns(firstPresentation), "invalidates an older sheet when a new one opens")
        expect(lifecycle.owns(secondPresentation), "keeps the latest sheet active")
        lifecycle.invalidate()
        expect(!lifecycle.owns(secondPresentation), "invalidates an in-flight save on context revocation")

        var recovery = CardPaymentRecordRecovery()
        expect(recovery.nextAction == .record, "starts by allowing one payment POST")
        expect(
            recovery.receive(.recordPaymentRefreshFailed("offline")) == .showRefreshError("offline"),
            "keeps a recorded payment open when its refresh fails"
        )
        expect(recovery.nextAction == .refresh, "retries only the summary refresh after a recorded payment")
    }

    private static func date(_ value: String) -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)!
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError("Regression failed: \(message)") }
    }
}

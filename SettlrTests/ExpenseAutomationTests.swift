import XCTest
@testable import Settlr

final class ExpenseAutomationTests: XCTestCase {
    private func card(_ id: String, label: String, digits: String? = nil, archived: Bool = false) -> CreditCard {
        CreditCard(id: id, label: label, lastFour: digits, network: nil, issuer: nil,
            creditLimitCents: nil, statementCutoffDay: nil, paymentDueDay: nil, notes: nil,
            archivedAt: archived ? "2026-10-01" : nil)
    }

    func testNewSplitPreservesReviewedPaymentAndHasReconciledTotal() throws {
        let expense = CreateExpenseBody(description: "Dinner", amountCents: 12345, occurredAt: "2026-10-08",
            categoryId: "food", paymentChannel: "credit_card", creditCardId: "travel")
        let draft = SplitDraft(automationExpense: expense)
        let body = draft.makeCreateBody()
        XCTAssertEqual(body.merchant, "Dinner")
        XCTAssertEqual(body.totalCents, 12345)
        XCTAssertEqual(body.occurredAt, "2026-10-08")
        XCTAssertEqual(body.paymentChannel, "credit_card")
        XCTAssertEqual(body.creditCardId, "travel")
        XCTAssertEqual(body.categoryId, "food")
        XCTAssertEqual(body.payer, "me")
        XCTAssertEqual(body.participantCount, 2)
        XCTAssertFalse(draft.reconciliation.requiresDecision)
        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(body)) as! [String: Any]
        XCTAssertEqual(encoded["categoryId"] as? String, "food")
    }

    private func split(payer: String, status: String = "locked") throws -> BillSplit {
        let json: [String: Any] = [
            "id": "split", "shareToken": "token", "merchant": "Dinner", "currency": "MXN",
            "occurredAt": "2026-10-08", "subtotalCents": 3000, "taxCents": 0, "tipCents": 0,
            "feeCents": 0, "totalCents": 3000, "status": status, "payer": payer,
            "createdAt": "2026-10-08", "items": [], "unclaimedItemsCents": 0,
            "unallocatedExtrasCents": 0, "outstandingCents": 1500,
            "participants": [["id": "me", "name": "You", "isOrganizer": true,
                "owedCents": 1500, "joinedAt": "2026-10-08"]]
        ]
        return try JSONDecoder().decode(BillSplit.self, from: JSONSerialization.data(withJSONObject: json))
    }

    func testLinkingRequiresTheAmountForTheSplitPayerAndCurrency() throws {
        let fronted = try split(payer: "me")
        XCTAssertTrue(AutomationSplitPayment.matches(amountCents: 3000, currency: "MXN", split: fronted))
        XCTAssertFalse(AutomationSplitPayment.matches(amountCents: 1500, currency: "MXN", split: fronted))
        XCTAssertFalse(AutomationSplitPayment.matches(amountCents: 3000, currency: "USD", split: fronted))
        let eachOwn = try split(payer: "each_own")
        XCTAssertTrue(AutomationSplitPayment.matches(amountCents: 1500, currency: "MXN", split: eachOwn))
        XCTAssertFalse(AutomationSplitPayment.matches(amountCents: 3000, currency: "MXN", split: eachOwn))
        XCTAssertFalse(AutomationSplitPayment.matches(amountCents: 1500, currency: "MXN", split: try split(payer: "each_own", status: "open")))
        XCTAssertFalse(AutomationSplitPayment.matches(amountCents: 3000, currency: "MXN", split: try split(payer: "unavailable")))
    }

    func testWalletSourceStaysDistinctFromQuickExpense() {
        XCTAssertFalse(AutomationExpenseDraft().isWalletPayment)
        XCTAssertTrue(AutomationExpenseDraft(isWalletPayment: true).isWalletPayment)
    }

    func testWalletCardMatchesLastFourAndNormalizedLabel() {
        let cards = [card("one", label: "Travel Visa", digits: "1234"), card("two", label: "Daily", digits: "5678")]
        XCTAssertEqual(WalletCardMatcher.match("Visa •••• 5678", cards: cards), "two")
        XCTAssertEqual(WalletCardMatcher.match("  TRAVEL vísa ", cards: cards), "one")
    }

    func testWalletCardDoesNotGuessForMissingOrAmbiguousDetails() {
        let cards = [card("one", label: "Visa", digits: "1234"), card("two", label: "Visa", digits: "1234")]
        XCTAssertNil(WalletCardMatcher.match("", cards: cards))
        XCTAssertNil(WalletCardMatcher.match("Visa", cards: cards))
        XCTAssertNil(WalletCardMatcher.match("Visa •••• 1234", cards: cards))
        XCTAssertNil(WalletCardMatcher.match("Mastercard", cards: cards))
    }

    func testWalletCardExcludesArchivedCards() {
        let cards = [card("old", label: "Daily", digits: "1234", archived: true), card("active", label: "Daily", digits: "5678")]
        XCTAssertEqual(WalletCardMatcher.match("Daily", cards: cards), "active")
        XCTAssertNil(WalletCardMatcher.match("Visa 1234", cards: cards))
    }

    func testWalletValuesPrefillAndTrimDescription() {
        let draft = AutomationExpenseDraft(amount: 12.34, merchant: "  Coffee Shop\n", card: " Visa ", name: "Purchase")
        XCTAssertEqual(draft.amountText, "12.34")
        XCTAssertEqual(draft.description, "Coffee Shop")
        XCTAssertEqual(draft.card, "Visa")
    }

    func testMissingMerchantFallsBackToTransactionName() {
        XCTAssertEqual(AutomationExpenseDraft(merchant: " \n", name: " Lunch ").description, "Lunch")
        XCTAssertEqual(AutomationExpenseDraft().description, "")
        XCTAssertEqual(AutomationExpenseDraft().amountText, "")
    }

    func testUnusableAmountsRequireManualEntry() {
        for amount in [0, -1, Double.nan, Double.infinity, Double(Int.max)] {
            XCTAssertNil(AutomationExpenseDraft(amount: amount).amount)
            XCTAssertEqual(AutomationExpenseDraft(amount: amount).amountText, "")
        }
    }

    @MainActor
    func testRepeatedPaymentsStaySeparateAndRemovingOnePreservesOthers() {
        let inbox = ExpenseAutomationInbox()
        let first = AutomationExpenseDraft(amount: 10, merchant: "Cafe")
        let second = AutomationExpenseDraft(amount: 10, merchant: "Cafe")
        inbox.enqueue(first)
        inbox.enqueue(second)
        XCTAssertEqual(inbox.drafts.map(\.id), [first.id, second.id])
        inbox.remove(id: first.id)
        XCTAssertEqual(inbox.drafts, [second])
        inbox.remove(id: first.id)
        XCTAssertEqual(inbox.drafts, [second])
        inbox.removeAll()
        XCTAssertTrue(inbox.drafts.isEmpty)
    }
}

import XCTest
@testable import Settlr

final class ExpenseAutomationTests: XCTestCase {
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

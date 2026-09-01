import XCTest
@testable import Settlr

final class GuidedSplitPresentationTests: XCTestCase {
    func testReceiptHeaderUsesDraftValuesAndCountsWarnings() {
        var draft = SplitDraft()
        draft.merchant = "DEICO RAMEN CONDESA"
        draft.paymentChannel = "cash"
        draft.items = [.init(name: "Soda", quantity: 1, unitPriceCents: 8_300, verification: .unverified)]
        draft.scanWarnings = ["Check total"]
        let value = SplitReceiptHeaderPresentation(draft: draft, totalCents: 8_300)
        XCTAssertEqual(value.merchant, "DEICO RAMEN CONDESA")
        XCTAssertEqual(value.paymentLabel, "Cash / debit")
        XCTAssertEqual(value.warningCount, 2)
    }

    func testSetupActionCopyFollowsDivisionMode() {
        XCTAssertEqual(GuidedSplitFlowPolicy.setupActionTitle(splitMode: "by_item", itemCount: 7), "Review 7 items")
        XCTAssertEqual(GuidedSplitFlowPolicy.setupActionTitle(splitMode: "even", itemCount: 0), "Check total")
    }

    func testItemEditorPreservesIdentityAndNormalizesQuantity() {
        let source = SplitDraft.Item(serverID: "item-1", name: "Soup", quantity: 2, unitPriceCents: 900, allocationMode: "units")
        let result = SplitItemEditDraft(item: source).committed(name: "Soup", quantity: 0, unitPriceCents: 950, allocationMode: "shared")
        XCTAssertEqual(result.serverID, "item-1")
        XCTAssertEqual(result.quantity, 1)
        XCTAssertEqual(result.unitPriceCents, 950)
        XCTAssertEqual(result.allocationMode, "shared")
    }

    func testGuestEditorKeepsBlankNamesForRequestNormalization() {
        var draft = SplitPeopleEditDraft(participants: SplitDraft().participants)
        draft.setHeadcount(2)
        XCTAssertEqual(draft.participants[1].name, "")
        draft.participants[1].name = "   "
        XCTAssertEqual(draft.participants[1].name, "   ")
    }
}

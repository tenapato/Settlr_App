import XCTest
@testable import Settlr

final class GuidedSplitPresentationTests: XCTestCase {
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
        draft.participants[1].name = "   "
        XCTAssertEqual(draft.participants[1].name, "   ")
    }
}

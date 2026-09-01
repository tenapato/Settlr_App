import XCTest
@testable import Settlr

final class GuidedSplitFlowStateTests: XCTestCase {
    func testByItemSetupRoutesThroughItems() {
        XCTAssertEqual(GuidedSplitFlowPolicy.nextStep(splitMode: "by_item"), .items)
        XCTAssertEqual(GuidedSplitFlowPolicy.backStep(from: .confirm, splitMode: "by_item"), .items)
    }

    func testEvenSetupSkipsItems() {
        XCTAssertEqual(GuidedSplitFlowPolicy.nextStep(splitMode: "even"), .confirm)
        XCTAssertEqual(GuidedSplitFlowPolicy.backStep(from: .confirm, splitMode: "even"), .setup)
    }

    func testUnverifiedPricedItemDoesNotBlockButMismatchDoes() {
        var draft = SplitDraft()
        draft.merchant = "Cafe"
        draft.items = [.init(name: "Lunch", quantity: 1, unitPriceCents: 1_000, verification: .unverified)]
        draft.selectedTotalCents = 2_000

        XCTAssertNil(GuidedSplitFlowPolicy.firstIssue(on: .items, draft: draft, totalEdited: true, isEditing: false, isOnline: true))
        XCTAssertEqual(
            GuidedSplitFlowPolicy.firstIssue(on: .confirm, draft: draft, totalEdited: true, isEditing: false, isOnline: true)?.field,
            .reconciliation
        )
    }

    func testScannerImportIsDirtyWithoutAFieldEdit() {
        let draft = SplitDraft()
        let snapshot = GuidedSplitSubmissionSnapshot(draft: draft, totalEdited: false)
        XCTAssertTrue(snapshot.hasUnsavedChanges(draft: draft, totalEdited: false, importedReceipt: true))
        XCTAssertFalse(snapshot.hasUnsavedChanges(draft: draft, totalEdited: false, importedReceipt: false))
    }
}

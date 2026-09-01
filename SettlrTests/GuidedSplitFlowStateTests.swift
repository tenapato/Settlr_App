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

    func testByItemNamedLineWithoutPriceBlocksConfirmation() {
        var draft = SplitDraft()
        draft.merchant = "Cafe"
        draft.items = [.init(name: "Lunch", quantity: 1, unitPriceCents: 0)]

        XCTAssertEqual(
            GuidedSplitFlowPolicy.firstIssue(on: .confirm, draft: draft, totalEdited: false, isEditing: false, isOnline: true)?.field,
            .items
        )
    }

    func testEvenSplitWithoutParticipantsBlocksConfirmation() {
        var draft = SplitDraft()
        draft.merchant = "Cafe"
        draft.splitMode = "even"
        draft.selectedTotalCents = 1_000
        draft.participants = []

        XCTAssertEqual(
            GuidedSplitFlowPolicy.firstIssue(on: .confirm, draft: draft, totalEdited: false, isEditing: false, isOnline: true)?.field,
            .payer
        )
    }

    func testChangingDivisionModePreservesTheDraft() {
        var draft = SplitDraft()
        draft.merchant = "Cafe"
        draft.participants.append(.init(id: nil, name: "Ana", isOrganizer: false))
        draft.items = [.init(name: "Lunch", quantity: 2, unitPriceCents: 1_250)]
        draft.selectedTotalCents = 2_500
        let originalItems = draft.items
        let originalParticipants = draft.participants

        draft.splitMode = "even"
        XCTAssertEqual(GuidedSplitFlowPolicy.nextStep(splitMode: draft.splitMode), .confirm)
        draft.splitMode = "by_item"

        XCTAssertEqual(GuidedSplitFlowPolicy.nextStep(splitMode: draft.splitMode), .items)
        XCTAssertEqual(draft.items, originalItems)
        XCTAssertEqual(draft.participants, originalParticipants)
        XCTAssertEqual(draft.selectedTotalCents, 2_500)
    }

    func testEveryGuidedStepHasTheCorrectBackTarget() {
        XCTAssertEqual(GuidedSplitFlowPolicy.backStep(from: .items, splitMode: "by_item"), .setup)
        XCTAssertEqual(GuidedSplitFlowPolicy.backStep(from: .confirm, splitMode: "by_item"), .items)
        XCTAssertEqual(GuidedSplitFlowPolicy.backStep(from: .confirm, splitMode: "even"), .setup)
    }
}

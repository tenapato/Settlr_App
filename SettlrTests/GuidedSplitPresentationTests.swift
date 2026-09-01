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

    func testItemsPresentationSeparatesReviewLinesWithoutInventingClaims() {
        var draft = SplitDraft()
        draft.participants.append(.init(id: nil, name: "Ana", isOrganizer: false))
        draft.items = [
            .init(name: "Soda", quantity: 1, unitPriceCents: 8_300, verification: .unverified),
            .init(name: "Soup", quantity: 2, unitPriceCents: 10_000, allocationMode: "units")
        ]

        let value = SplitItemsPresentation(draft: draft)

        XCTAssertEqual(value.itemCount, 2)
        XCTAssertEqual(value.participantCount, 2)
        XCTAssertEqual(value.reviewCount, 1)
        XCTAssertEqual(value.subtotalCents, 28_300)
        XCTAssertEqual(SplitItemFilter.allCases, [.needsReview, .all])
        XCTAssertEqual(value.items(for: .needsReview).map(\.name), ["Soda"])
        XCTAssertEqual(value.items(for: .all).map(\.name), ["Soda", "Soup"])
    }

    func testItemsPresentationFallsBackToAllWhenNoItemsNeedReview() {
        var draft = SplitDraft()
        draft.items = [.init(name: "Soup", quantity: 1, unitPriceCents: 10_000)]

        let value = SplitItemsPresentation(draft: draft)

        XCTAssertEqual(value.availableFilters, [.all])
        XCTAssertEqual(value.normalizedFilter(.needsReview), .all)
        XCTAssertEqual(value.items(for: .needsReview).count, 0)
        XCTAssertEqual(value.items(for: .all).map(\.name), ["Soup"])
    }

    func testConfirmPresentationIncludesEvenShareAndMaterialDifference() {
        var draft = SplitDraft()
        draft.merchant = "Cafe"
        draft.splitMode = "even"
        draft.participants.append(.init(id: nil, name: "Ana", isOrganizer: false))
        draft.items = [.init(name: "Bill", quantity: 1, unitPriceCents: 8_000)]
        draft.selectedTotalCents = 10_000

        let value = SplitConfirmPresentation(draft: draft, totalEdited: true)

        XCTAssertEqual(value.effectiveTotalCents, 10_000)
        XCTAssertEqual(value.evenShareCents, 5_000)
        XCTAssertEqual(value.differenceCents, 2_000)
    }

    func testPrimaryActionCopyMatchesOutcome() {
        XCTAssertEqual(GuidedSplitPrimaryAction.create.title, "Create split")
        XCTAssertEqual(GuidedSplitPrimaryAction.saveChanges.title, "Save changes")
        XCTAssertEqual(GuidedSplitPrimaryAction.saveOnPhone.title, "Save on this phone")
    }

    func testConfirmDivisionSummaryRoutesToDivisionSetupField() {
        XCTAssertEqual(SplitConfirmPresentation.divisionSetupField, .division)
    }
}

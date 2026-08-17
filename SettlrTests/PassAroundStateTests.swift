import XCTest
@testable import Settlr

final class PassAroundStateTests: XCTestCase {
    func testOnePersonRequiresExplicitSoloChoiceBeforeStarting() {
        // This catches pass-around silently opening as "1 of 1" without the
        // organizer deliberately choosing a one-person flow.
        var state = PassAroundState(participantIDs: ["organizer"])

        XCTAssertFalse(state.canStart)
        XCTAssertFalse(state.start())

        state.continueWithJustMe()

        XCTAssertTrue(state.canStart)
        XCTAssertTrue(state.start())
        XCTAssertEqual(state.currentParticipantID, "organizer")
    }

    func testAdoptingRefreshedPeoplePreservesCurrentParticipantByID() {
        // This catches refresh/conflict handling that retains an array index and
        // consequently hands the phone to a different person after insertion.
        var state = PassAroundState(participantIDs: ["organizer", "ana", "leo"])
        XCTAssertTrue(state.start())
        state.selectNext()
        XCTAssertEqual(state.currentParticipantID, "ana")

        state.adoptParticipantIDs(["new", "organizer", "ana", "leo"])

        XCTAssertEqual(state.currentParticipantID, "ana")
        XCTAssertEqual(state.orderedParticipantIDs, ["organizer", "ana", "leo", "new"])
        XCTAssertEqual(state.position, 2)
    }

    func testLocalReorderingChangesPassSequenceWithoutChangingCurrentPerson() {
        // This catches local table reordering that accidentally identifies the
        // current person by their old position.
        var state = PassAroundState(participantIDs: ["organizer", "ana", "leo"])
        XCTAssertTrue(state.start())
        state.selectNext()

        state.moveParticipant(id: "leo", by: -1)

        XCTAssertEqual(state.orderedParticipantIDs, ["organizer", "leo", "ana"])
        XCTAssertEqual(state.currentParticipantID, "ana")
        XCTAssertEqual(state.position, 3)
    }

    func testUnitControlNeverExceedsAvailableCapacity() {
        // This catches plus/minus controls sending an impossible desired
        // quantity or treating units held by somebody else as available.
        let state = SplitClaimControlState(
            allocationMode: "units",
            totalQuantity: 3,
            claimedQuantity: 2,
            participantQuantity: 1
        )

        XCTAssertEqual(state.mine, 1)
        XCTAssertEqual(state.available, 1)
        XCTAssertEqual(state.total, 3)
        XCTAssertEqual(state.decrementedQuantity, 0)
        XCTAssertEqual(state.incrementedQuantity, 2)
        XCTAssertTrue(state.canDecrement)
        XCTAssertTrue(state.canIncrement)

        let full = SplitClaimControlState(
            allocationMode: "units",
            totalQuantity: 3,
            claimedQuantity: 3,
            participantQuantity: 1
        )
        XCTAssertFalse(full.canIncrement)
        XCTAssertEqual(full.incrementedQuantity, 1)
    }

    func testSharedControlUsesExplicitShareAndRemoveActions() {
        // This catches shared plates being rendered as exclusive quantity rows
        // or using an ambiguous whole-row checkbox.
        let unclaimed = SplitClaimControlState(
            allocationMode: "shared",
            totalQuantity: 1,
            claimedQuantity: 2,
            participantQuantity: 0
        )
        XCTAssertTrue(unclaimed.isShared)
        XCTAssertEqual(unclaimed.sharedActionTitle, "Share item")
        XCTAssertEqual(unclaimed.sharedDesiredQuantity, 1)

        let claimed = SplitClaimControlState(
            allocationMode: "shared",
            totalQuantity: 1,
            claimedQuantity: 3,
            participantQuantity: 1
        )
        XCTAssertEqual(claimed.sharedActionTitle, "Remove share")
        XCTAssertEqual(claimed.sharedDesiredQuantity, 0)
    }

    func testClaimBodyEncodesDesiredQuantityInsteadOfLegacyBoolean() throws {
        // This catches a client regression back to all-or-nothing boolean claims.
        let body = BillSplitClaimBody(itemId: "item-1", quantity: 2, participantId: "ana")
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(body)) as? [String: Any]
        )

        XCTAssertEqual(object["itemId"] as? String, "item-1")
        XCTAssertEqual(object["quantity"] as? Int, 2)
        XCTAssertEqual(object["participantId"] as? String, "ana")
        XCTAssertNil(object["claimed"])
    }

    func testByItemCreateNormalizesBlankGuestNames() {
        // This catches the pass-around server receiving unnamed rows even
        // though the UI promises numbered fallback names.
        var draft = SplitDraft()
        draft.merchant = "Cafe"
        draft.splitMode = "by_item"
        draft.items = [.init(name: "Coffee", unitPriceCents: 500)]
        draft.selectedTotalCents = 500
        draft.participants.append(.init(id: nil, name: "Ana", isOrganizer: false))
        draft.participants.append(.init(id: nil, name: "  ", isOrganizer: false))

        let body = draft.makeCreateBody()

        XCTAssertEqual(body.participantCount, 3)
        XCTAssertEqual(body.participantNames, ["Ana", "Person 3"])
    }

    func testPublicUnitControlUsesViewerQuantityAndRemainingCapacity() throws {
        // This catches the native public link falling back to a boolean claim
        // even though the server returned two units for the current viewer.
        let participant = try JSONDecoder().decode(
            PublicSplitParticipant.self,
            from: Data(#"{"id":"guest","name":"Ana","isOrganizer":false,"claimedItemIds":["tacos"],"claimQuantities":{"tacos":2},"owedCents":2000,"settled":false}"#.utf8)
        )
        let control = SplitClaimControlState(
            allocationMode: "units",
            totalQuantity: 4,
            claimedQuantity: 3,
            participantQuantity: participant.claimQuantities["tacos"] ?? 0
        )

        XCTAssertEqual(control.mine, 2)
        XCTAssertEqual(control.available, 1)
        XCTAssertEqual(control.total, 4)
        XCTAssertEqual(control.decrementedQuantity, 1)
        XCTAssertEqual(control.incrementedQuantity, 3)
    }

    func testLegacyPublicParticipantDefaultsMissingClaimQuantities() throws {
        // This catches the additive quantity field making a response from an
        // older server undecodable during rollout.
        let participant = try JSONDecoder().decode(
            PublicSplitParticipant.self,
            from: Data(#"{"id":"guest","name":"Ana","isOrganizer":false,"claimedItemIds":["plate"],"owedCents":1000,"settled":false}"#.utf8)
        )

        XCTAssertEqual(participant.claimQuantities, [:])
    }
}

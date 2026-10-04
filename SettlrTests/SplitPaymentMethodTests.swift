import XCTest
@testable import Settlr

final class SplitPaymentMethodTests: XCTestCase {
    func testOlderDetailLoadCannotOverwriteNewerMutation() {
        var gate = BillSplitDetailResponseGate()
        let oldLoad = gate.beginLoad()
        let mutation = gate.beginMutation()

        XCTAssertFalse(gate.shouldAdopt(load: oldLoad))
        XCTAssertTrue(gate.shouldAdopt(mutation: mutation))
        XCTAssertTrue(gate.commitMutation(mutation))
        XCTAssertFalse(gate.shouldAdopt(mutation: mutation))
    }

    func testOlderOverlappingDetailLoadCannotOverwriteNewerRefresh() {
        var gate = BillSplitDetailResponseGate()
        let oldLoad = gate.beginLoad()
        let newLoad = gate.beginLoad()

        XCTAssertFalse(gate.shouldAdopt(load: oldLoad))
        XCTAssertTrue(gate.shouldAdopt(load: newLoad))
    }

    func testConflictCopyDistinguishesSuccessfulAndFailedRefresh() {
        XCTAssertEqual(
            BillSplitPaymentConflictPresentation.message(didRefresh: true),
            "This split changed on another screen. It has been refreshed; try saving again."
        )
        XCTAssertEqual(
            BillSplitPaymentConflictPresentation.message(didRefresh: false),
            "This split changed on another screen, but it could not be refreshed. Reconnect and try again."
        )
    }

    func testCashBodyEncodesExplicitNullCard() throws {
        // This catches stale card IDs surviving a cash mutation because the
        // request omitted creditCardId instead of clearing it explicitly.
        let body = BillSplitPaymentMethodBody(
            version: 7,
            paymentChannel: "cash",
            creditCardId: nil
        )

        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(body)) as? [String: Any]
        )
        XCTAssertEqual(object["version"] as? Int, 7)
        XCTAssertEqual(object["paymentChannel"] as? String, "cash")
        XCTAssertTrue(object["creditCardId"] is NSNull)
    }

    func testCashCanSaveWithoutCardAndChangingToCashClearsSelection() {
        // This catches validation requiring a card for cash or accidentally
        // resubmitting an old card ID after the channel changes.
        var state = SplitPaymentMethodEditorState(
            version: 7,
            paymentChannel: "credit_card",
            creditCardId: "card-1"
        )

        state.selectPaymentChannel("cash")

        XCTAssertTrue(state.canSave)
        XCTAssertNil(state.creditCardId)
    }

    func testCreditCardRequiresSelection() {
        // This catches sending a credit-card channel the server must reject
        // because no workspace card was selected.
        let state = SplitPaymentMethodEditorState(
            version: 7,
            paymentChannel: "credit_card",
            creditCardId: nil
        )

        XCTAssertFalse(state.canSave)
    }

    func testCurrentCopyResolvesCardLabelAndLastFour() {
        // This catches organizer detail exposing a raw card ID or omitting the
        // identifying last four digits.
        let card = CreditCard(
            id: "card-1",
            label: "Travel",
            lastFour: "4242",
            network: "Visa",
            issuer: nil,
            creditLimitCents: nil,
            statementCutoffDay: nil,
            paymentDueDay: nil,
            notes: nil
        )
        let state = SplitPaymentMethodEditorState(
            version: 7,
            paymentChannel: "credit_card",
            creditCardId: card.id
        )

        XCTAssertEqual(state.displayValue(cards: [card]), "Travel •••• 4242")
    }

    func testStaleRefreshUpdatesVersionWithoutDiscardingPendingSelection() {
        // This catches a 409 refresh resetting the form to the server's old
        // method and making the organizer repeat their choice.
        var state = SplitPaymentMethodEditorState(
            version: 7,
            paymentChannel: "credit_card",
            creditCardId: "card-new"
        )

        state.adoptRefreshedVersion(8)

        XCTAssertEqual(state.version, 8)
        XCTAssertEqual(state.paymentChannel, "credit_card")
        XCTAssertEqual(state.creditCardId, "card-new")
    }
}

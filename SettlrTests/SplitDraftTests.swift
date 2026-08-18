import XCTest
@testable import Settlr

final class SplitDraftTests: XCTestCase {
    func testExistingSplitRoundTripsEveryEditableFieldIntoVersionedBody() throws {
        // This catches any draft extraction/body builder that drops a money,
        // payment, participant, allocation, or stable-identity field.
        let split = try decodeSplit()

        let draft = SplitDraft(split: split)
        let body = draft.makeEditBody(version: split.version)

        XCTAssertEqual(body.version, 7)
        XCTAssertEqual(body.merchant, "Cafe Central")
        XCTAssertEqual(body.occurredAt, "2026-08-16")
        XCTAssertEqual(body.currency, "MXN")
        XCTAssertEqual(body.payer, "each_own")
        XCTAssertEqual(body.splitMode, "by_item")
        XCTAssertEqual(body.paymentChannel, "credit_card")
        XCTAssertEqual(body.creditCardId, "card-9")
        XCTAssertEqual(body.categoryId, "cat-food")
        XCTAssertEqual(body.taxCents, 160)
        XCTAssertEqual(body.tipCents, 240)
        XCTAssertEqual(body.feeCents, 75)
        XCTAssertEqual(body.totalCents, 2_475)
        XCTAssertTrue(body.mismatchAcknowledged)
        XCTAssertEqual(body.items.count, 2)
        XCTAssertEqual(body.items[0].id, "item-1")
        XCTAssertEqual(body.items[0].name, "Tacos 23")
        XCTAssertEqual(body.items[0].quantity, 2)
        XCTAssertEqual(body.items[0].unitPriceCents, 500)
        XCTAssertEqual(body.items[0].allocationMode, "units")
        XCTAssertEqual(body.items[1].id, "item-2")
        XCTAssertEqual(body.items[1].allocationMode, "shared")
        XCTAssertEqual(body.participants.map(\.id), ["person-me", "person-2"])
        XCTAssertEqual(body.participants.map(\.name), ["Patricio", "Ana"])
        XCTAssertEqual(body.participants.map(\.isOrganizer), [true, false])
    }

    func testScanDraftBuildsCreateBodyWithoutInventingVerifiedMoney() {
        // This catches create-mode regressions where parser verification,
        // participant setup, allocation mode, or an explicit total is lost.
        let scan = ScannedReceipt(
            parser: .server,
            merchant: "Taqueria",
            items: [
                ScannedReceiptItem(
                    name: "TACO",
                    quantity: 3,
                    unitPriceCents: 250,
                    verification: .unverified
                )
            ],
            taxCents: 100,
            tipCents: 120,
            totalCents: 1_070,
            warnings: ["Review one row"]
        )
        var draft = SplitDraft(scan: scan)
        draft.occurredAt = SplitDraft.day(from: "2026-08-16")!
        draft.payer = "each_own"
        draft.splitMode = "by_item"
        draft.feeCents = 100
        draft.paymentChannel = "cash"
        draft.participants.append(.init(id: nil, name: "Ana", isOrganizer: false))

        let body = draft.makeCreateBody()

        XCTAssertEqual(body.merchant, "Taqueria")
        XCTAssertEqual(body.occurredAt, "2026-08-16")
        XCTAssertEqual(body.items[0].quantity, 3)
        XCTAssertEqual(body.items[0].unitPriceCents, 250)
        XCTAssertEqual(body.items[0].allocationMode, "units")
        XCTAssertEqual(body.feeCents, 100)
        XCTAssertEqual(body.totalCents, 1_070)
        XCTAssertEqual(body.payer, "each_own")
        XCTAssertEqual(body.participantCount, 2)
        XCTAssertEqual(body.participantNames, ["Ana"])
        XCTAssertEqual(draft.unverifiedItems.map(\.name), ["TACO"])
    }

    func testReconciliationUsesLargerOfOnePesoAndPointOnePercentTolerance() {
        // This catches rounding thresholds that mistakenly force a decision for
        // a one-peso receipt difference or ignore a material discrepancy.
        var draft = makeDraft(itemTotal: 199_800, selectedTotal: 200_000)
        XCTAssertEqual(draft.reconciliation.toleranceCents, 200)
        XCTAssertEqual(draft.reconciliation.kind, .rounding)

        draft.selectedTotalCents = 200_001
        XCTAssertEqual(draft.reconciliation.kind, .shortfall)
        XCTAssertEqual(draft.reconciliation.differenceCents, 201)

        draft.selectedTotalCents = 199_599
        XCTAssertEqual(draft.reconciliation.kind, .overshoot)
        XCTAssertEqual(draft.reconciliation.differenceCents, -201)
    }

    func testMismatchActionsNeverSilentlyReplaceSelectedTotal() {
        // This catches saving a material scan mismatch by silently overwriting
        // the printed total instead of recording the user's explicit choice.
        var draft = makeDraft(itemTotal: 12_000, selectedTotal: 10_000)

        XCTAssertTrue(draft.reconciliation.requiresDecision)
        XCTAssertFalse(draft.mismatchAcknowledged)
        XCTAssertEqual(draft.selectedTotalCents, 10_000)

        draft.confirmKeepReceiptTotal()
        XCTAssertTrue(draft.mismatchAcknowledged)
        XCTAssertEqual(draft.selectedTotalCents, 10_000)

        draft.useCalculatedTotal()
        XCTAssertFalse(draft.mismatchAcknowledged)
        XCTAssertEqual(draft.selectedTotalCents, 12_000)
        XCTAssertFalse(draft.reconciliation.requiresDecision)
    }

    func testLegacySplitDefaultsNewDraftFieldsWithoutBreakingDecode() throws {
        // This catches additive server fields making older cached responses
        // undecodable or turning a missing version into an unsafe overwrite.
        let data = Data(legacySplitJSON.utf8)
        let split = try JSONDecoder().decode(BillSplit.self, from: data)
        let draft = SplitDraft(split: split)

        XCTAssertEqual(split.version, 0)
        XCTAssertEqual(draft.paymentChannel, "cash")
        XCTAssertNil(draft.creditCardId)
        XCTAssertEqual(draft.items[0].allocationMode, "shared")
        XCTAssertFalse(draft.mismatchAcknowledged)
    }

    func testEditBodyNumbersBlankGuestNamesLikeCreateDoes() throws {
        // The create endpoint expands blank optional names. Complete edits have
        // a stricter body, so the reusable draft must preserve the same UX.
        var draft = SplitDraft(split: try decodeSplit())
        draft.participants[1].name = "   "

        let body = draft.makeEditBody(version: 7)

        XCTAssertEqual(body.participants[1].name, "Person 2")
    }

    func testFinancialEditPlanOnlyMarksChangedOrRemovedClaimedItems() throws {
        let split = try decodeSplit()
        var draft = SplitDraft(split: split)

        // Metadata edits do not affect claims. A price change does, while an
        // unchanged claimed item and an unclaimed changed item do not need a
        // destructive confirmation.
        draft.items[0].unitPriceCents = 550
        draft.items[1].unitPriceCents = 1_100
        let plan = draft.claimImpact(comparedTo: split)

        XCTAssertEqual(plan.itemIDsRequiringConfirmation, ["item-1"])
        XCTAssertEqual(plan.itemNamesRequiringConfirmation, ["Tacos 23"])
        XCTAssertTrue(plan.removedItemIDs.isEmpty)
    }

    func testFinancialEditPlanIncludesRemovedClaimedItems() throws {
        let split = try decodeSplit()
        var draft = SplitDraft(split: split)
        draft.items.removeAll { $0.serverID == "item-1" }

        let plan = draft.claimImpact(comparedTo: split)

        XCTAssertEqual(plan.itemIDsRequiringConfirmation, ["item-1"])
        XCTAssertEqual(plan.removedItemIDs, ["item-1"])
    }

    func testEditBodyClearsOnlyConfirmedFinancialChanges() throws {
        let split = try decodeSplit()
        var draft = SplitDraft(split: split)
        draft.items[0].unitPriceCents = 550
        draft.items[1].unitPriceCents = 1_100

        let body = draft.makeEditBody(version: split.version, clearClaimsFor: ["item-1"])

        XCTAssertEqual(body.items[0].clearClaims, true)
        XCTAssertNil(body.items[1].clearClaims)
    }

    private func makeDraft(itemTotal: Int, selectedTotal: Int) -> SplitDraft {
        var draft = SplitDraft(scan: ScannedReceipt(
            parser: .onDevice,
            merchant: "Test",
            items: [
                ScannedReceiptItem(
                    name: "Line",
                    quantity: 1,
                    unitPriceCents: itemTotal,
                    verification: .verified
                )
            ],
            taxCents: 0,
            tipCents: 0,
            totalCents: selectedTotal,
            warnings: []
        ))
        draft.selectedTotalCents = selectedTotal
        return draft
    }

    private func decodeSplit() throws -> BillSplit {
        let json = #"""
        {
          "id":"split-1","shareToken":"token","shareUrl":null,
          "merchant":"Cafe Central","currency":"MXN","occurredAt":"2026-08-16",
          "subtotalCents":2000,"taxCents":160,"tipCents":240,"feeCents":75,"totalCents":2475,
          "status":"open","version":7,"mismatchAcknowledged":true,
          "payer":"each_own","splitMode":"by_item","paymentChannel":"credit_card",
          "creditCardId":"card-9","categoryId":"cat-food","expenseId":null,"createdAt":"2026-08-16",
          "items":[
            {"id":"item-1","name":"Tacos 23","quantity":2,"allocationMode":"units","claimedQuantity":1,"availableQuantity":1,"unitPriceCents":500,"lineTotalCents":1000,"sortOrder":0},
            {"id":"item-2","name":"Salsa","quantity":1,"allocationMode":"shared","claimedQuantity":0,"availableQuantity":null,"unitPriceCents":1000,"lineTotalCents":1000,"sortOrder":1}
          ],
          "participants":[
            {"id":"person-me","name":"Patricio","isOrganizer":true,"claimedItemIds":[],"claimQuantities":{},"owedCents":1000,"shareCents":null,"settledAt":null,"incomeId":null,"joinedAt":"2026-08-16"},
            {"id":"person-2","name":"Ana","isOrganizer":false,"claimedItemIds":[],"claimQuantities":{},"owedCents":1475,"shareCents":null,"settledAt":null,"incomeId":null,"joinedAt":"2026-08-16"}
          ],
          "unclaimedItemsCents":2000,"unallocatedExtrasCents":475,"outstandingCents":0
        }
        """#
        return try JSONDecoder().decode(BillSplit.self, from: Data(json.utf8))
    }

    private var legacySplitJSON: String {
        #"""
        {
          "id":"legacy","shareToken":"token","merchant":"Old","currency":"MXN","occurredAt":"2026-08-16",
          "subtotalCents":500,"taxCents":0,"tipCents":0,"feeCents":0,"totalCents":500,
          "status":"open","payer":"me","splitMode":"by_item","expenseId":"expense","createdAt":"2026-08-16",
          "items":[{"id":"item","name":"Coffee","quantity":1,"unitPriceCents":500,"lineTotalCents":500,"sortOrder":0}],
          "participants":[{"id":"me","name":"Me","isOrganizer":true,"claimedItemIds":[],"owedCents":500,"shareCents":null,"settledAt":null,"incomeId":null,"joinedAt":"2026-08-16"}],
          "unclaimedItemsCents":500,"unallocatedExtrasCents":0,"outstandingCents":0
        }
        """#
    }
}

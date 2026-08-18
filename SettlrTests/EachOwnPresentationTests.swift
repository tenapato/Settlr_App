import XCTest
@testable import Settlr

final class EachOwnPresentationTests: XCTestCase {
    func testQueuedCreateRoundTripPreservesEachOwnPayer() throws {
        // This catches an offline retry silently dropping `each_own` and later
        // creating an organizer-paid split when connectivity returns.
        let body = CreateBillSplitBody(
            merchant: "Cafe",
            occurredAt: "2026-08-17",
            items: [BillSplitItemBody(name: "Coffee", quantity: 1, unitPriceCents: 500)],
            taxCents: 0,
            tipCents: 0,
            feeCents: 0,
            totalCents: 500,
            paymentChannel: "cash",
            creditCardId: nil,
            payer: "each_own"
        )
        let pending = PendingSplit(
            id: UUID(uuidString: "ABCD1234-0000-0000-0000-000000000001")!,
            idempotencyKey: "retry-key",
            userId: "user",
            workspaceId: "workspace",
            body: body,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let restored = try JSONDecoder().decode(
            PendingSplit.self,
            from: JSONEncoder().encode(pending)
        )

        XCTAssertEqual(restored.body.payer, "each_own")
    }

    func testLegacyQueuedCreateWithoutPayerDefaultsToExplicitOrganizerPaidMode() throws {
        // This catches additive payer enforcement making already-durable queued
        // requests undecodable after an app update.
        let data = Data(#"{"merchant":"Old Cafe","occurredAt":"2026-08-17","items":[],"taxCents":0,"tipCents":0,"feeCents":0,"totalCents":500,"paymentChannel":"cash","creditCardId":null}"#.utf8)

        let restored = try JSONDecoder().decode(CreateBillSplitBody.self, from: data)

        XCTAssertEqual(restored.payer, "me")
    }

    func testEachOwnPresentationContainsOnlyIndividualShareLanguage() {
        // This catches either split screen drifting back to reimbursement copy
        // even though the persisted payer says everyone paid directly.
        let presentation = SplitAccountingPresentation(payerMode: .eachOwn)
        XCTAssertEqual(presentation.eachOwnSummaryTitle, "Everyone paid their own share")
        XCTAssertEqual(presentation.eachOwnOtherSharesLabel, "Everyone else's shares")
        XCTAssertEqual(presentation.eachOwnShareLabel, "Your share")
        XCTAssertEqual(presentation.eachOwnExpenseNote, "Only your share was recorded as an expense.")
        let renderedCopy = [
            presentation.eachOwnSummaryTitle,
            presentation.eachOwnOtherSharesLabel,
            presentation.eachOwnShareLabel,
            presentation.eachOwnExpenseNote,
            presentation.expenseSubtitle(
                participantCount: 3,
                guestCount: 2,
                settledGuestCount: 0
            ),
            presentation.peopleSectionTitle,
            presentation.participantStatus(isOrganizer: true, isSettled: false),
            presentation.participantStatus(isOrganizer: false, isSettled: false),
            presentation.participantSubtitle(
                isOrganizer: true,
                isEvenSplit: false,
                claimedItemCount: 1
            ),
            presentation.participantSubtitle(
                isOrganizer: false,
                isEvenSplit: false,
                claimedItemCount: 2
            ),
            presentation.lockedHeaderStatus(outstandingCents: 4_000),
            presentation.emptyPeopleMessage(isOpen: true) ?? "",
            presentation.lockButtonCaption(isOpen: true),
        ].joined(separator: " | ")

        XCTAssertTrue(renderedCopy.contains("Your share"))
        XCTAssertTrue(renderedCopy.contains("Individual shares"))
        for prohibited in [
            "Paid back to you",
            "Your net cost",
            "Paid the bill",
            "Owes you",
            "Nobody has joined yet",
            "owed to you",
            "reimbursement",
            "reimbursements",
        ] {
            XCTAssertFalse(renderedCopy.localizedCaseInsensitiveContains(prohibited))
        }
    }

    func testMissingLegacyPayerRequiresReviewInsteadOfChoosingReimbursement() throws {
        // This catches a missing/unknown payer taking the historical fallback
        // branch that portrayed the organizer as having fronted the whole bill.
        let split = try JSONDecoder().decode(
            BillSplit.self,
            from: Data(legacySplitWithoutPayerJSON.utf8)
        )

        XCTAssertEqual(split.payer, "unavailable")
        XCTAssertEqual(split.payerMode, .unavailable)
        XCTAssertEqual(SplitDraft(split: split).payer, "")
        XCTAssertEqual(split.accountingPresentation.summaryMode, .reviewRequired)
        XCTAssertEqual(
            split.accountingPresentation.reviewMessage,
            "Split mode unavailable — open to review"
        )
        XCTAssertFalse(split.accountingPresentation.allowsSettlementActions)
    }

    private var legacySplitWithoutPayerJSON: String {
        #"""
        {
          "id":"legacy","shareToken":"token","merchant":"Old Cafe","currency":"MXN","occurredAt":"2026-08-17",
          "subtotalCents":500,"taxCents":0,"tipCents":0,"feeCents":0,"totalCents":500,
          "status":"open","splitMode":"by_item","paymentChannel":"cash","createdAt":"2026-08-17",
          "items":[{"id":"item","name":"Coffee","quantity":1,"unitPriceCents":500,"lineTotalCents":500,"sortOrder":0}],
          "participants":[{"id":"me","name":"Patricio","isOrganizer":true,"claimedItemIds":[],"owedCents":500,"shareCents":null,"settledAt":null,"incomeId":null,"joinedAt":"2026-08-17"}],
          "unclaimedItemsCents":500,"unallocatedExtrasCents":0,"outstandingCents":0
        }
        """#
    }
}

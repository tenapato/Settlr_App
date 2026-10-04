import XCTest
@testable import Settlr

final class EachOwnPresentationTests: XCTestCase {
    func testSummaryStatusUsesPayerAwareLanguage() throws {
        // This catches closed each-own splits drifting back to collection copy,
        // and missing legacy payer data being guessed as organizer-paid.
        let cases: [(status: String, payer: String?, outstanding: Int?, expected: String)] = [
            ("open", "me", nil, "Claiming"),
            ("locked", "each_own", 4_000, "Completed"),
            ("settled", "each_own", 0, "Completed"),
            ("locked", "me", 0, "Collecting"),
            ("settled", "me", 0, "Settled"),
            ("locked", nil, 0, "Needs review"),
        ]

        for item in cases {
            let summary = try decodeSummary(
                status: item.status,
                payer: item.payer,
                outstandingCents: item.outstanding
            )
            XCTAssertEqual(
                BillSplitSummaryStatusPresentation.label(for: summary),
                item.expected,
                "status=\(item.status), payer=\(item.payer ?? "missing")"
            )
        }
    }

    func testLockedOrganizerPaidSummaryPreservesAmountOwedCopy() throws {
        // This catches payer-awareness accidentally flattening the existing
        // amount-due chip into a generic collecting label.
        let summary = try decodeSummary(status: "locked", payer: "me", outstandingCents: 4_250)

        XCTAssertEqual(
            BillSplitSummaryStatusPresentation.label(for: summary),
            "\(formatSplitMoney(4_250, currency: "MXN")) owed"
        )
    }

    func testLegacySummaryWithoutPayerDecodesAsUnavailable() throws {
        // This catches additive list data breaking old responses or silently
        // treating their absent payer as if the organizer fronted the bill.
        let summary = try decodeSummary(status: "locked", payer: nil, outstandingCents: 0)

        XCTAssertNil(summary.payer)
        XCTAssertEqual(summary.payerMode, .unavailable)
    }

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

    func testResultPresentationKeepsSettlementCopyPayerCorrect() {
        let organizerPaid = SplitResultPresentation(payerMode: .organizerPaid)
        XCTAssertEqual(organizerPaid.statusHeadline, "Ready to settle.")
        XCTAssertEqual(organizerPaid.organizerShareLabel, "Your share")
        XCTAssertEqual(organizerPaid.amountToCollectLabel, "Amount to collect")
        XCTAssertEqual(organizerPaid.participantStatus(isOrganizer: true, isSettled: false), "Paid the bill")
        XCTAssertEqual(organizerPaid.participantStatus(isOrganizer: false, isSettled: false), "Owes you")
        XCTAssertEqual(organizerPaid.participantStatus(isOrganizer: false, isSettled: true), "Settled")

        let eachOwn = SplitResultPresentation(payerMode: .eachOwn)
        XCTAssertEqual(eachOwn.statusHeadline, "Everyone paid their own share")
        XCTAssertEqual(eachOwn.organizerShareLabel, "Your share")
        XCTAssertEqual(eachOwn.otherSharesLabel, "Everyone else's shares")
        XCTAssertNil(eachOwn.amountToCollectLabel)
        XCTAssertEqual(eachOwn.participantStatus(isOrganizer: false, isSettled: false), "Paid their own")
    }

    func testResultPresentationOnlySettlesClosedOrganizerPaidSplits() {
        let presentation = SplitResultPresentation(payerMode: .organizerPaid)

        XCTAssertFalse(presentation.showsSettlementControls(isOpen: true, hasOwnerContext: true))
        XCTAssertTrue(presentation.showsSettlementControls(isOpen: false, hasOwnerContext: true))
        XCTAssertFalse(presentation.showsSettlementControls(isOpen: false, hasOwnerContext: false))
        XCTAssertEqual(presentation.statusHeadline(isOpen: true), "Finish claiming to settle.")
    }

    func testEachOwnOtherSharesAggregateExcludesUnclaimedAmount() {
        // Guest shares are the only amount shown as "everyone else's shares";
        // an unclaimed remainder must not be presented as another person's share.
        let totalCents = 8_000
        let organizerShareCents = 2_200
        let unclaimedCents = 2_000
        let guestShares = [2_200, 1_600]
        XCTAssertEqual(
            SplitResultPresentation.aggregateOtherShares(participantShares: guestShares),
            totalCents - organizerShareCents - unclaimedCents
        )
    }

    func testUnavailableResultDoesNotShowParticipantBalances() {
        let presentation = SplitResultPresentation(payerMode: .unavailable)
        XCTAssertFalse(presentation.showsParticipantBalances)
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

    private func decodeSummary(
        status: String,
        payer: String?,
        outstandingCents: Int?
    ) throws -> BillSplitSummary {
        var object: [String: Any] = [
            "id": "summary",
            "shareToken": "token",
            "merchant": "Cafe",
            "currency": "MXN",
            "occurredAt": "2026-08-17",
            "totalCents": 10_000,
            "status": status,
            "participantCount": 3,
            "settledCount": 0,
            "pendingCount": 2,
        ]
        if let payer { object["payer"] = payer }
        if let outstandingCents { object["outstandingCents"] = outstandingCents }
        let data = try JSONSerialization.data(withJSONObject: object)
        return try JSONDecoder().decode(BillSplitSummary.self, from: data)
    }
}

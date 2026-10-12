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

    func testItemFilterAccessibilityValueAnnouncesMatchingCountAndSelection() {
        var draft = SplitDraft()
        draft.items = [
            .init(name: "Soda", quantity: 1, unitPriceCents: 8_300, verification: .unverified),
            .init(name: "Soup", quantity: 1, unitPriceCents: 10_000)
        ]

        let value = SplitItemsPresentation(draft: draft)

        XCTAssertEqual(value.accessibilityValue(for: .needsReview, isSelected: true), "1 item, Selected")
        XCTAssertEqual(value.accessibilityValue(for: .all, isSelected: false), "2 items, Not selected")
    }

    func testActiveTipPresetTogglesToZeroAndInactivePresetUsesCalculatedTip() {
        let base = 10_005
        let activeTip = TipPreset.cents(base: base, percent: 12)

        XCTAssertEqual(SplitMoneyEditorSheet.toggledTipCents(base: base, currentCents: activeTip, percent: 12), 0)
        XCTAssertEqual(
            SplitMoneyEditorSheet.toggledTipCents(base: base, currentCents: activeTip, percent: 15),
            TipPreset.cents(base: base, percent: 15)
        )
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
        XCTAssertEqual(value.receiptTotalCents, 10_000)
        XCTAssertEqual(value.differenceCents, 2_000)
        XCTAssertEqual(value.acknowledgementExplanation, "The receipt total is higher than the calculated total. The scan likely missed a line.")
    }

    func testConfirmPresentationShowsPositiveRoundingDifferenceWithoutDecision() {
        var draft = SplitDraft()
        draft.merchant = "Cafe"
        draft.items = [.init(name: "Bill", quantity: 1, unitPriceCents: 10_000)]
        draft.selectedTotalCents = 10_050

        let value = SplitConfirmPresentation(draft: draft, totalEdited: true)

        XCTAssertEqual(value.receiptTotalCents, 10_050)
        XCTAssertEqual(value.differenceCents, 50)
        XCTAssertEqual(value.reconciliation.kind, .rounding)
        XCTAssertFalse(value.reconciliation.requiresAcknowledgement)
        XCTAssertNil(value.acknowledgementExplanation)
        XCTAssertFalse(value.reconciliation.requiresDecision)
    }

    func testConfirmPresentationRequiresDecisionForNegativeRoundingDifference() {
        var draft = SplitDraft()
        draft.merchant = "Cafe"
        draft.items = [.init(name: "Bill", quantity: 1, unitPriceCents: 10_050)]
        draft.selectedTotalCents = 10_000

        let value = SplitConfirmPresentation(draft: draft, totalEdited: true)

        XCTAssertEqual(value.receiptTotalCents, 10_000)
        XCTAssertEqual(value.differenceCents, -50)
        XCTAssertEqual(value.reconciliation.kind, .rounding)
        XCTAssertTrue(value.reconciliation.requiresAcknowledgement)
        XCTAssertTrue(value.reconciliation.requiresDecision)
        XCTAssertEqual(value.acknowledgementExplanation, "The receipt total is lower than the calculated total. The scan likely duplicated or overcounted a line.")
    }

    func testConfirmPresentationExplainsLikelyDuplicatedLineWhenReceiptIsLower() {
        var draft = SplitDraft()
        draft.merchant = "Cafe"
        draft.items = [.init(name: "Bill", quantity: 1, unitPriceCents: 12_000)]
        draft.selectedTotalCents = 10_000

        let value = SplitConfirmPresentation(draft: draft, totalEdited: true)

        XCTAssertEqual(value.differenceCents, -2_000)
        XCTAssertEqual(value.acknowledgementExplanation, "The receipt total is lower than the calculated total. The scan likely duplicated or overcounted a line.")
    }

    func testConfirmPresentationOmitsReceiptRowsWithoutTotalProvenance() {
        var draft = SplitDraft()
        draft.items = [.init(name: "Bill", quantity: 1, unitPriceCents: 10_000)]
        draft.selectedTotalCents = 8_000

        let value = SplitConfirmPresentation(draft: draft, totalEdited: false)

        XCTAssertNil(value.receiptTotalCents)
        XCTAssertNil(value.differenceCents)
        XCTAssertNil(value.acknowledgementExplanation)
    }

    func testPrimaryActionCopyMatchesOutcome() {
        XCTAssertEqual(GuidedSplitPrimaryAction.create.title, "Create split")
        XCTAssertEqual(GuidedSplitPrimaryAction.saveChanges.title, "Save changes")
        XCTAssertEqual(GuidedSplitPrimaryAction.saveOnPhone.title, "Save on this phone")
    }

    func testConfirmDivisionSummaryRoutesToDivisionSetupField() {
        XCTAssertEqual(SplitConfirmPresentation.divisionSetupField, .division)
    }

    func testConfirmPresentationDisclosesOfflineSaveStatus() {
        let value = SplitConfirmPresentation(draft: SplitDraft(), totalEdited: false, isOnline: false)
        let offlineEdit = SplitConfirmPresentation(
            draft: SplitDraft(),
            totalEdited: false,
            isOnline: false,
            isEditing: true
        )

        XCTAssertEqual(value.offlineStatus, "Will save on this phone")
        XCTAssertFalse(value.requiresConnectionCheck)
        XCTAssertNil(SplitConfirmPresentation(draft: SplitDraft(), totalEdited: false, isOnline: true).offlineStatus)
        XCTAssertEqual(offlineEdit.offlineStatus, "Reconnect to save changes")
        XCTAssertTrue(offlineEdit.requiresConnectionCheck)
    }

    func testGuidedFieldsMapToStableOwningSteps() {
        XCTAssertEqual(GuidedSplitField.merchant.owningStep, .setup)
        XCTAssertEqual(GuidedSplitField.participants.owningStep, .setup)
        XCTAssertEqual(GuidedSplitField.payer.owningStep, .setup)
        XCTAssertEqual(GuidedSplitField.division.owningStep, .setup)
        XCTAssertEqual(GuidedSplitField.paymentMethod.owningStep, .setup)
        XCTAssertEqual(GuidedSplitField.items.owningStep, .items)
        XCTAssertEqual(GuidedSplitField.item(UUID()).owningStep, .items)
        XCTAssertEqual(GuidedSplitField.total.owningStep, .confirm)
        XCTAssertEqual(GuidedSplitField.reconciliation.owningStep, .confirm)
        XCTAssertEqual(GuidedSplitField.onlineEdit.owningStep, .confirm)
    }

    func testMissingParticipantsTargetsPeopleEditor() {
        var draft = SplitDraft()
        draft.merchant = "Cafe"
        draft.splitMode = "even"
        draft.selectedTotalCents = 1_000
        draft.participants = []

        let issue = GuidedSplitFlowPolicy.firstIssue(
            on: .confirm,
            draft: draft,
            totalEdited: true,
            isEditing: false,
            isOnline: true
        )

        XCTAssertEqual(issue?.field, .participants)
        XCTAssertEqual(issue?.step, .setup)
    }

    func testInvalidExistingItemTargetsItsEditorRow() {
        let invalidID = UUID()
        var draft = SplitDraft()
        draft.merchant = "Cafe"
        draft.items = [.init(localID: invalidID, name: "Soup", quantity: 1, unitPriceCents: 0)]

        let issue = GuidedSplitFlowPolicy.firstIssue(
            on: .confirm,
            draft: draft,
            totalEdited: false,
            isEditing: false,
            isOnline: true
        )

        XCTAssertEqual(issue?.field, .item(invalidID))
        XCTAssertEqual(issue?.step, .items)
    }

    func testEmptyItemListTargetsAddItemControl() {
        var draft = SplitDraft()
        draft.merchant = "Cafe"
        draft.items = [.init()]

        let issue = GuidedSplitFlowPolicy.firstIssue(
            on: .confirm,
            draft: draft,
            totalEdited: false,
            isEditing: false,
            isOnline: true
        )

        XCTAssertEqual(issue?.field, .items)
    }

    func testFocusRequestInvalidationRejectsDeferredRequest() {
        var state = GuidedSplitFocusRequestState()
        let participants = state.request(.participants)
        XCTAssertTrue(state.isCurrent(participants))

        state.invalidate()
        XCTAssertFalse(state.isCurrent(participants))
    }

    func testNewFocusRequestSupersedesPreviousRequest() {
        var state = GuidedSplitFocusRequestState()
        let firstItem = state.request(.item(UUID()))
        let payer = state.request(.payer)

        XCTAssertFalse(state.isCurrent(firstItem))
        XCTAssertTrue(state.isCurrent(payer))
    }

    func testFixableServerRejectionRemainsDurableAndReturnsNeedsAttention() {
        let entry = makePendingSplit()

        let transition = SplitSyncPolicy.transition(
            entry,
            after: .giveUp(.rejected("Give every item a name.")),
            errorMessage: "Give every item a name.",
            now: Date(timeIntervalSince1970: 1_000),
            jitter: 1
        )

        XCTAssertEqual(transition.entry.blockedReason, .rejected("Give every item a name."))
        XCTAssertEqual(transition.entry.attemptCount, 1)
        guard case .needsAttention(let persisted) = transition.outcome else {
            return XCTFail("A persisted rejected entry must not look queued or be discarded")
        }
        XCTAssertEqual(persisted.id, entry.id)
        XCTAssertEqual(persisted.idempotencyKey, entry.idempotencyKey)
    }

    func testNonfixableServerRejectionReturnsNeedsAttentionWithExactReason() {
        let entry = makePendingSplit()

        let transition = SplitSyncPolicy.transition(
            entry,
            after: .giveUp(.quotaReached("Your monthly split limit has been reached.")),
            errorMessage: "Your monthly split limit has been reached.",
            now: Date(timeIntervalSince1970: 1_000),
            jitter: 1
        )

        guard case .needsAttention(let persisted) = transition.outcome else {
            return XCTFail("A blocked persisted entry must have a distinct result")
        }
        XCTAssertEqual(persisted.blockedReason, .quotaReached("Your monthly split limit has been reached."))
        XCTAssertFalse(persisted.isWaiting)
    }

    func testCorrectedRejectedEntryKeepsItsOriginalIdempotencyKey() {
        var entry = makePendingSplit()
        let originalKey = entry.idempotencyKey
        var correctedBody = entry.body
        correctedBody.idempotencyKey = "replacement-key-that-must-not-be-used"

        entry.prepareForRetry(with: correctedBody)

        XCTAssertEqual(entry.idempotencyKey, originalKey)
        XCTAssertEqual(entry.body.idempotencyKey, originalKey)
        XCTAssertEqual(entry.state, .queued)
        XCTAssertEqual(entry.attemptCount, 0)
        XCTAssertNil(entry.nextAttemptAt)
        XCTAssertNil(entry.lastErrorMessage)
    }

    func testPendingResultPresentationDoesNotPromiseBlockedUpload() {
        var blocked = makePendingSplit()
        blocked.state = .needsAttention(.featureDisabled("Bill splitting is disabled."))

        let presentation = SplitPendingResultPresentation(entry: blocked)

        XCTAssertEqual(presentation.title, "Needs attention")
        XCTAssertEqual(presentation.reason, "Bill splitting is disabled.")
        XCTAssertEqual(presentation.actionTitle, "View pending splits")
        XCTAssertFalse(presentation.isWaiting)
    }

    func testPendingResultPresentationKeepsOrdinaryQueuedCopy() {
        let presentation = SplitPendingResultPresentation(entry: makePendingSplit())

        XCTAssertEqual(presentation.title, "Waiting to upload")
        XCTAssertNil(presentation.reason)
        XCTAssertEqual(presentation.actionTitle, "Done")
        XCTAssertTrue(presentation.isWaiting)
    }

    func testEditorContinuationCarriesBlockedQueueIdentityAcrossReview() {
        let blockedID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        var draft = SplitDraft()
        draft.merchant = "Still editable"

        let continuation = SplitEditorContinuation(
            draft: draft,
            totalEdited: true,
            blockedEntryID: blockedID
        )

        XCTAssertEqual(continuation.draft.merchant, "Still editable")
        XCTAssertTrue(continuation.totalEdited)
        XCTAssertEqual(continuation.blockedEntryID, blockedID)
    }

    func testSubmissionRouteFallsBackToOneNewEntryWhenBlockedEntryIsGone() {
        let missingID = UUID(uuidString: "FFFFFFFF-1111-2222-3333-444444444444")!

        let route = PendingSplitSubmissionRoute.resolve(
            replacing: missingID,
            entries: [makePendingSplit()]
        )

        XCTAssertEqual(route, .create)
    }

    func testSubmissionRouteResubmitsWhenBlockedEntryStillExists() {
        let entry = makePendingSplit()

        let route = PendingSplitSubmissionRoute.resolve(
            replacing: entry.id,
            entries: [entry]
        )

        XCTAssertEqual(route, .resubmit(entry.id))
    }

    func testSplitCompletionRendersResultBeforeNotifyingPresenter() {
        let entry = makePendingSplit()
        var events: [String] = []
        var renderedEntryID: UUID?

        SplitScanCompletionCoordinator.complete(
            .queued(entry),
            apply: { split, pending, stage in
                XCTAssertNil(split)
                renderedEntryID = pending?.id
                if case .result = stage { events.append("render") }
            },
            notify: { _ in
                XCTAssertEqual(renderedEntryID, entry.id)
                events.append("notify")
            }
        )

        XCTAssertEqual(events, ["render", "notify"])
    }

    func testSaveHandoffIsConsumedOnceAfterDismissal() {
        var handoff = SplitScanHandoff()
        let entry = makePendingSplit()
        handoff.receive(.queued(entry))
        guard case .queued(let result)? = handoff.takeAfterDismissal() else {
            return XCTFail("A durable save must be handed back after dismissal")
        }
        XCTAssertEqual(result.id, entry.id)
        XCTAssertNil(handoff.takeAfterDismissal())
    }

    func testRejectedOrCancelledCreationDoesNotNavigateParent() {
        var handoff = SplitScanHandoff()
        XCTAssertNil(handoff.takeAfterDismissal())
        handoff.receive(.rejected("Try again"))
        XCTAssertNil(handoff.takeAfterDismissal())
        handoff.receive(.queued(makePendingSplit()))
        XCTAssertNotNil(handoff.takeAfterDismissal())
    }

    func testDuplicateCallbackDoesNotReplaceSuccessfulHandoff() {
        var handoff = SplitScanHandoff()
        let entry = makePendingSplit()
        handoff.receive(.queued(entry))
        handoff.receive(.rejected("Late failure"))
        guard case .queued(let result)? = handoff.takeAfterDismissal() else {
            return XCTFail("A later callback must not overwrite the saved outcome")
        }
        XCTAssertEqual(result.id, entry.id)
    }

    func testSharedBottleKeepsPurchaseQuantitySeparateFromPeopleCount() {
        let item = SplitDraft.Item(name: "Bottle", quantity: 1, unitPriceCents: 250_000)
        let edited = SplitItemEditDraft(item: item).committed(
            name: "Bottle", quantity: 1, unitPriceCents: 250_000, allocationMode: "shared"
        )
        XCTAssertEqual(edited.quantity, 1)
        XCTAssertEqual(edited.lineTotalCents, 250_000)
        XCTAssertEqual(edited.allocationMode, "shared")
        var draft = SplitDraft()
        draft.items = [edited]
        XCTAssertEqual(draft.makeCreateBody().items.first?.allocationMode, "shared")
    }

    func testItemMoneyRejectsInvalidAndOverflowingInput() {
        XCTAssertEqual(SplitItemEditorSheet.validMoney("2500.00"), 250_000)
        XCTAssertEqual(SplitItemEditorSheet.validMoney("12,34"), 1234)
        for input in ["", "abc", "-1", "nan", "inf", "1e100"] {
            XCTAssertNil(SplitItemEditorSheet.validMoney(input), input)
        }
    }

    func testReceiptConfirmationPreservesPrintedTotalAndAllowsSubmission() {
        var draft = SplitDraft()
        draft.items = [.init(name: "Lunch", quantity: 1, unitPriceCents: 1000)]
        draft.selectedTotalCents = 1500
        XCTAssertTrue(draft.reconciliation.requiresDecision)
        draft.confirmKeepReceiptTotal()
        XCTAssertEqual(draft.makeCreateBody().totalCents, 1500)
        XCTAssertTrue(draft.makeCreateBody().mismatchAcknowledged == true)
        XCTAssertFalse(draft.reconciliation.requiresDecision)
        draft.useCalculatedTotal()
        XCTAssertEqual(draft.selectedTotalCents, 1000)
        XCTAssertFalse(draft.mismatchAcknowledged)
    }

    private func makePendingSplit() -> PendingSplit {
        let id = UUID(uuidString: "12345678-1234-1234-1234-123456789ABC")!
        return PendingSplit(
            id: id,
            idempotencyKey: id.uuidString,
            userId: "user-1",
            workspaceId: "workspace-1",
            body: CreateBillSplitBody(
                merchant: "Cafe",
                occurredAt: "2026-09-01",
                items: [BillSplitItemBody(name: "Lunch", quantity: 1, unitPriceCents: 1_000)],
                taxCents: 0,
                tipCents: 0,
                feeCents: 0,
                totalCents: 1_000,
                paymentChannel: "cash",
                creditCardId: nil,
                idempotencyKey: id.uuidString
            ),
            createdAt: Date(timeIntervalSince1970: 0)
        )
    }
}

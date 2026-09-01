import SwiftUI

private enum SplitPresentedEditor: Identifiable {
    case receipt
    case people
    case item(UUID)
    case newItem(SplitDraft.Item)
    case money(SplitMoneyField)

    var id: String {
        switch self {
        case .receipt: "receipt"
        case .people: "people"
        case .item(let id): "item-\(id.uuidString)"
        case .newItem(let item): "new-item-\(item.id.uuidString)"
        case .money(let field): "money-\(field.id)"
        }
    }
}

private extension SplitMoneyField {
    var id: String {
        switch self {
        case .total: "total"
        case .tax: "tax"
        case .tip: "tip"
        case .fee: "fee"
        }
    }
}

/// Owns one split draft across Setup, Items, and Confirm while keeping receipt
/// recovery, feature normalization, queueing, and editing at the coordinator boundary.
struct SplitCreateSheet: View {
    let workspaceId: String
    let vm: BillSplitVM
    var prefill: ScannedReceipt?
    var notice: String?
    var editingSplit: BillSplit? = nil
    var initialDraft: SplitDraft? = nil
    var initialTotalEdited: Bool? = nil
    var onBackToReview: ((SplitDraft, Bool) -> Void)? = nil
    var onCancelFlow: (() -> Void)? = nil
    var dismissOnSave: Bool = true
    let onSaved: (SplitSaveOutcome) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    private let queue = PendingSplitQueue.shared
    private let network = NetworkMonitor.shared

    @State private var draft = SplitDraft()
    @State private var totalEdited = false
    @State private var creditCards: [CreditCard] = []
    @State private var showScanner = false
    @State private var isScanning = false
    @State private var scanNotice: String?
    @State private var showReceiptSettings = false
    @State private var errorMessage: String?
    @State private var photoRecovery = ReceiptPhotoRecovery()
    @State private var showPhotoRecovery = false
    @State private var showKeepMismatchConfirmation = false
    @State private var showClaimChangeConfirmation = false
    @State private var pendingClaimClearIDs: Set<String> = []
    @State private var hasInitialized = false
    @State private var openedEditVersion: Int?
    @State private var isSubmitting = false

    @State private var path: [GuidedSplitStep] = []
    @State private var validationIssue: GuidedSplitValidationIssue?
    @State private var itemFilter: SplitItemFilter = .all
    @State private var presentedEditor: SplitPresentedEditor?
    @State private var cardLoadState: SplitCardLoadState = .idle
    @State private var initialSnapshot: GuidedSplitSubmissionSnapshot?
    @State private var showDiscardConfirmation = false

    private var isEditing: Bool { editingSplit != nil }
    private var canUseCreditCards: Bool { appState.currentUser?.has(.creditCards) == true }
    private var effectiveTotalCents: Int {
        totalEdited ? draft.selectedTotalCents : draft.calculatedTotalCents
    }
    private var submissionDraft: SplitDraft {
        var result = draft
        if !totalEdited { result.selectedTotalCents = result.calculatedTotalCents }
        return result
    }
    private var canSave: Bool {
        GuidedSplitFlowPolicy.firstIssue(
            on: .confirm,
            draft: submissionDraft,
            totalEdited: totalEdited,
            isEditing: isEditing,
            isOnline: network.isOnline
        ) == nil && !isScanning
    }
    private var primaryAction: GuidedSplitPrimaryAction {
        if isEditing { return .saveChanges }
        return network.isOnline ? .create : .saveOnPhone
    }
    private var scannerImportedReceipt: Bool { onBackToReview != nil }

    var body: some View {
        NavigationStack(path: $path) {
            guidedScreen(.setup)
                .navigationDestination(for: GuidedSplitStep.self) { step in
                    guidedScreen(step)
                }
        }
        .fullScreenCover(isPresented: $showScanner) {
            ReceiptCaptureView(
                onCapture: { image in
                    showScanner = false
                    handleCapture(image)
                },
                busyMessage: nil,
                errorMessage: nil
            )
        }
        .confirmationDialog(
            "Photo parsing failed",
            isPresented: $showPhotoRecovery,
            titleVisibility: .visible
        ) {
            Button("Retry photo") { runPhotoRecovery(preference: .serverPhoto) }
            Button("On server (text only)") { runPhotoRecovery(preference: .server) }
            Button("Manual entry") { continueWithManualEntry() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The captured photo is kept only in this editor session while you choose how to continue.")
        }
        .sheet(isPresented: $showReceiptSettings) {
            SettingsView()
        }
        .sheet(item: $presentedEditor) { editor in
            editorSheet(editor)
        }
        .alert("Keep the receipt total?", isPresented: $showKeepMismatchConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Keep receipt total") { draft.confirmKeepReceiptTotal() }
        } message: {
            Text("The item lines and total differ materially. Keep this total only after checking the receipt for missing or duplicated rows.")
        }
        .alert("Clear existing claims?", isPresented: $showClaimChangeConfirmation) {
            Button("Cancel", role: .cancel) { pendingClaimClearIDs = [] }
            Button("Save and clear claims", role: .destructive) {
                let ids = pendingClaimClearIDs
                pendingClaimClearIDs = []
                submitEdit(clearClaimsFor: ids)
            }
        } message: {
            Text(claimChangeMessage)
        }
        .alert("Discard this split?", isPresented: $showDiscardConfirmation) {
            Button("Keep editing", role: .cancel) {}
            Button("Discard", role: .destructive) { cancelFlow() }
        } message: {
            Text("Your receipt or split changes will be lost.")
        }
        .task(id: canUseCreditCards) {
            if canUseCreditCards {
                await loadCards()
            } else {
                cardLoadState = .idle
            }
        }
        .onAppear { applyInitialDraftOnce() }
        .onChange(of: canUseCreditCards) { _, enabled in
            if !enabled { normalizeCardPaymentState() }
        }
        .onDisappear { photoRecovery.clear() }
        .interactiveDismissDisabled(isScanning || isSubmitting)
    }

    @ViewBuilder
    private func guidedScreen(_ step: GuidedSplitStep) -> some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    SplitProgressRail(step: step)
                    if let scanNotice, step == .setup {
                        Text(scanNotice)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Theme.muted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Theme.expense)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    stepView(step)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .scrollDismissesKeyboard(.interactively)
            .disabled(isScanning || isSubmitting)

            if isScanning { scanningOverlay }
        }
        .navigationTitle(title(for: step))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { navigationToolbar(for: step) }
    }

    @ViewBuilder
    private func stepView(_ step: GuidedSplitStep) -> some View {
        switch step {
        case .setup:
            SplitSetupStepView(
                draft: $draft,
                totalCents: effectiveTotalCents,
                cards: canUseCreditCards ? creditCards : [],
                cardLoadState: canUseCreditCards ? cardLoadState : .idle,
                validationIssue: validationIssue,
                onEditReceipt: { presentedEditor = .receipt },
                onEditPeople: { presentedEditor = .people },
                onScanAgain: beginScan,
                onOpenParserSettings: { showReceiptSettings = true },
                onRetryCards: { Task { await loadCards() } },
                onContinue: continueFromSetup
            )
        case .items:
            SplitItemsStepView(
                draft: $draft,
                filter: $itemFilter,
                validationIssue: validationIssue,
                onEditItem: { presentedEditor = .item($0.id) },
                onAddItem: { presentedEditor = .newItem(SplitDraft.Item()) },
                onContinue: continueFromItems
            )
        case .confirm:
            SplitConfirmStepView(
                draft: $draft,
                totalEdited: $totalEdited,
                presentation: .init(draft: submissionDraft, totalEdited: totalEdited),
                primaryAction: primaryAction,
                validationIssue: validationIssue,
                isSubmitting: isSubmitting,
                onEditSetupValue: editSetupValue,
                onEditMoney: { presentedEditor = .money($0) },
                onKeepReceiptTotal: { showKeepMismatchConfirmation = true },
                onUseCalculatedTotal: {
                    draft.useCalculatedTotal()
                    totalEdited = true
                    validationIssue = nil
                },
                onSubmit: validateAndSave
            )
        }
    }

    @ToolbarContentBuilder
    private func navigationToolbar(for step: GuidedSplitStep) -> some ToolbarContent {
        if step == .setup, onBackToReview != nil {
            ToolbarItemGroup(placement: .navigationBarLeading) {
                Button("Back", action: backToReview)
                Button("Cancel", action: requestCancel)
            }
        } else if step == .setup {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", action: requestCancel)
            }
        } else {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Cancel", action: requestCancel)
            }
        }
    }

    private var scanningOverlay: some View {
        ZStack {
            Theme.scrim.ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView().tint(Theme.buttonInk)
                Text("Reading receipt…")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                if let legend = vm.scanPrivacyLegend {
                    Text(legend)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(24)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    @ViewBuilder
    private func editorSheet(_ editor: SplitPresentedEditor) -> some View {
        switch editor {
        case .receipt:
            SplitReceiptDetailsSheet(merchant: draft.merchant, occurredAt: draft.occurredAt) { merchant, date in
                draft.merchant = merchant
                draft.occurredAt = date
                validationIssue = nil
            }
        case .people:
            SplitPeopleEditorSheet(participants: draft.participants) { participants in
                draft.participants = participants
                validationIssue = nil
            }
        case .item(let id):
            if let item = draft.items.first(where: { $0.id == id }) {
                SplitItemEditorSheet(
                    item: item,
                    onCommit: commitItem,
                    onRemove: { removeItem(id) }
                )
            }
        case .newItem(let item):
            SplitItemEditorSheet(item: item) { committed in
                draft.items.append(committed)
                draft.mismatchAcknowledged = false
                validationIssue = nil
            }
        case .money(let field):
            SplitMoneyEditorSheet(
                kind: field,
                cents: cents(for: field),
                tipBaseCents: tipBaseCents,
                onCommit: { commitMoney($0, field: field) }
            )
        }
    }

    private func title(for step: GuidedSplitStep) -> String {
        switch step {
        case .setup: isEditing ? "Edit Bill Split" : "Split a Bill"
        case .items: "Review Items"
        case .confirm: "Confirm Split"
        }
    }

    // MARK: - Navigation and validation

    private func continueFromSetup() {
        errorMessage = nil
        if let issue = firstSetupIssue() {
            validationIssue = issue
            return
        }
        validationIssue = nil
        path.append(GuidedSplitFlowPolicy.nextStep(splitMode: draft.splitMode))
    }

    private func continueFromItems() {
        errorMessage = nil
        if let issue = submissionIssue().map(issueOwnedByItsEditor), issue.step == .items {
            validationIssue = issue
            return
        }
        validationIssue = nil
        path.append(.confirm)
    }

    private func validateAndSave() {
        errorMessage = nil
        normalizeCardPaymentState()
        if let issue = submissionIssue().map(issueOwnedByItsEditor) {
            present(issue)
            return
        }
        save()
    }

    private func firstSetupIssue() -> GuidedSplitValidationIssue? {
        if draft.merchant.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .init(step: .setup, field: .merchant, message: "Add a merchant name.")
        }
        if draft.participants.isEmpty {
            return .init(step: .setup, field: .payer, message: "Add at least one participant.")
        }
        if BillSplitPayerMode(persistedValue: draft.payer) == .unavailable {
            return .init(step: .setup, field: .payer, message: "Choose who paid.")
        }
        if draft.paymentChannel == "credit_card", draft.creditCardId == nil {
            return .init(step: .setup, field: .paymentMethod, message: "Select a credit card.")
        }
        return nil
    }

    private func submissionIssue() -> GuidedSplitValidationIssue? {
        GuidedSplitFlowPolicy.firstIssue(
            on: .confirm,
            draft: submissionDraft,
            totalEdited: totalEdited,
            isEditing: isEditing,
            isOnline: network.isOnline
        )
    }

    private func issueOwnedByItsEditor(_ issue: GuidedSplitValidationIssue) -> GuidedSplitValidationIssue {
        let step: GuidedSplitStep
        switch issue.field {
        case .merchant, .payer, .division, .paymentMethod:
            step = .setup
        case .items:
            step = .items
        case .total, .reconciliation, .onlineEdit:
            step = .confirm
        }
        return .init(step: step, field: issue.field, message: issue.message)
    }

    private func present(_ issue: GuidedSplitValidationIssue) {
        validationIssue = issue
        switch issue.step {
        case .setup:
            path.removeAll()
        case .items:
            path = [.items]
        case .confirm:
            if path.last != .confirm { path.append(.confirm) }
        }
    }

    private func editSetupValue(_ field: GuidedSplitField) {
        validationIssue = nil
        switch field {
        case .total:
            presentedEditor = .money(.total)
        default:
            path.removeAll()
        }
    }

    private func backToReview() {
        photoRecovery.clear()
        onBackToReview?(draft, totalEdited)
    }

    private func requestCancel() {
        guard initialSnapshot?.hasUnsavedChanges(
            draft: draft,
            totalEdited: totalEdited,
            importedReceipt: scannerImportedReceipt
        ) == true else {
            cancelFlow()
            return
        }
        showDiscardConfirmation = true
    }

    private func cancelFlow() {
        photoRecovery.clear()
        if let onCancelFlow { onCancelFlow() } else { dismiss() }
    }

    // MARK: - Editors

    private func commitItem(_ item: SplitDraft.Item) {
        guard let index = draft.items.firstIndex(where: { $0.id == item.id }) else { return }
        draft.items[index] = item
        draft.mismatchAcknowledged = false
        validationIssue = nil
    }

    private func removeItem(_ id: UUID) {
        draft.items.removeAll { $0.id == id }
        if draft.items.isEmpty { draft.items = [SplitDraft.Item()] }
        draft.mismatchAcknowledged = false
        validationIssue = nil
    }

    private func cents(for field: SplitMoneyField) -> Int {
        switch field {
        case .total: effectiveTotalCents
        case .tax: draft.taxCents
        case .tip: draft.tipCents
        case .fee: draft.feeCents
        }
    }

    private func commitMoney(_ cents: Int, field: SplitMoneyField) {
        switch field {
        case .total:
            draft.selectedTotalCents = cents
            totalEdited = true
        case .tax:
            draft.taxCents = cents
        case .tip:
            if totalEdited {
                draft.selectedTotalCents = TipPreset.retotal(
                    selectedTotal: draft.selectedTotalCents,
                    replacing: draft.tipCents,
                    with: cents
                )
            }
            draft.tipCents = cents
        case .fee:
            draft.feeCents = cents
        }
        draft.mismatchAcknowledged = false
        validationIssue = nil
    }

    private var tipBaseCents: Int {
        if draft.itemSubtotalCents > 0 { return draft.itemSubtotalCents + draft.taxCents }
        return max(0, effectiveTotalCents - draft.tipCents)
    }

    // MARK: - Scan recovery

    private func beginScan() {
        scanNotice = nil
        errorMessage = nil
        showScanner = true
    }

    private func handleCapture(_ image: UIImage) {
        vm.beginReceiptScan()
        photoRecovery.clear()
        isScanning = true
        errorMessage = nil
        Task {
            defer { isScanning = false }
            var recognizedText: String?
            do {
                let text = try await Task.detached(priority: .userInitiated) {
                    try ReceiptOCR.recognizeText(in: image)
                }.value
                recognizedText = text
                applyScan(try await vm.scanReceipt(workspaceId: workspaceId, text: text, image: image))
            } catch {
                if let recognizedText, vm.lastScanPreference == .serverPhoto {
                    photoRecovery.retain(image: image, ocrText: recognizedText)
                    errorMessage = error.localizedDescription
                    showPhotoRecovery = true
                } else {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func runPhotoRecovery(preference: ReceiptParserPreference) {
        guard let image = photoRecovery.image, let text = photoRecovery.ocrText else { return }
        vm.beginReceiptScan()
        isScanning = true
        errorMessage = nil
        Task {
            defer { isScanning = false }
            do {
                let parsed = try await vm.scanReceipt(
                    workspaceId: workspaceId,
                    text: text,
                    image: preference == .serverPhoto ? image : nil,
                    preference: preference
                )
                applyScan(parsed)
            } catch {
                errorMessage = error.localizedDescription
                showPhotoRecovery = true
            }
        }
    }

    private func continueWithManualEntry() {
        vm.beginReceiptScan()
        photoRecovery.clear()
        errorMessage = nil
        scanNotice = "Enter the receipt items manually."
    }

    private func applyInitialDraftOnce() {
        guard !hasInitialized else { return }
        hasInitialized = true
        if scanNotice == nil, let notice { scanNotice = notice }
        if let initialDraft {
            draft = initialDraft
            totalEdited = initialTotalEdited ?? true
        } else if let editingSplit {
            draft = SplitDraft(split: editingSplit)
            openedEditVersion = editingSplit.version
            totalEdited = true
        } else if let prefill {
            applyScan(prefill)
        } else if draft.participants.count == 1 {
            draft.participants.append(.init(id: nil, name: "", isOrganizer: false))
        }
        normalizeCardPaymentState()
        initialSnapshot = GuidedSplitSubmissionSnapshot(draft: draft, totalEdited: totalEdited)
    }

    private func applyScan(_ parsed: ScannedReceipt) {
        photoRecovery.clear()
        if draft.merchant.trimmingCharacters(in: .whitespaces).isEmpty, let scanned = parsed.merchant {
            draft.merchant = scanned
        }
        draft.items = parsed.items.map {
            SplitDraft.Item(
                name: $0.name,
                quantity: max(1, $0.quantity),
                unitPriceCents: $0.unitPriceCents,
                verification: $0.verification
            )
        }
        draft.items.append(SplitDraft.Item())
        draft.taxCents = parsed.taxCents
        draft.tipCents = parsed.tipCents
        draft.scanWarnings = parsed.warnings
        draft.mismatchAcknowledged = false
        if parsed.totalCents > 0 {
            draft.selectedTotalCents = parsed.totalCents
            totalEdited = true
        } else {
            draft.selectedTotalCents = draft.calculatedTotalCents
            totalEdited = false
        }
        scanNotice = nil
        validationIssue = nil
    }

    // MARK: - Cards

    private func loadCards() async {
        guard canUseCreditCards else {
            cardLoadState = .idle
            return
        }
        creditCards = OfflineSessionCache.creditCards(workspaceId: workspaceId)
            .filter { !$0.isArchived }
        cardLoadState = .refreshing
        do {
            let response: CreditCardsResponse = try await APIClient.shared.fetch(
                Endpoints.creditCards(workspaceId)
            )
            OfflineSessionCache.saveCreditCards(response.creditCards, workspaceId: workspaceId)
            creditCards = response.creditCards.filter { !$0.isArchived }
            cardLoadState = .idle
        } catch {
            if error is CancellationError { return }
            cardLoadState = .failed(error.localizedDescription)
        }
    }

    private func normalizeCardPaymentState() {
        guard !canUseCreditCards else { return }
        draft.paymentChannel = "cash"
        draft.creditCardId = nil
        creditCards = []
        cardLoadState = .idle
    }

    // MARK: - Submission

    private func save() {
        normalizeCardPaymentState()
        guard canSave else {
            if let issue = submissionIssue().map(issueOwnedByItsEditor) { present(issue) }
            return
        }
        let bodyDraft = submissionDraft

        if let editingSplit {
            guard network.isOnline else {
                errorMessage = "Editing needs an internet connection."
                return
            }
            guard openedEditVersion != nil else {
                errorMessage = "Reload this split before editing."
                return
            }
            let impact = bodyDraft.claimImpact(comparedTo: editingSplit)
            if impact.requiresConfirmation {
                pendingClaimClearIDs = Set(impact.itemIDsRequiringConfirmation)
                showClaimChangeConfirmation = true
                return
            }
            submitEdit(clearClaimsFor: [])
            return
        }

        guard let userId = appState.currentUser?.id else {
            errorMessage = "Sign in again to save this split."
            return
        }
        errorMessage = nil
        isSubmitting = true
        let body = bodyDraft.makeCreateBody()
        Task {
            defer { isSubmitting = false }
            let entry = queue.makeEntry(userId: userId, workspaceId: workspaceId, body: body)
            let outcome = await queue.save(entry)
            switch outcome {
            case .created, .queued:
                onSaved(outcome)
                if dismissOnSave { dismiss() }
            case .rejected(let message):
                errorMessage = message
            }
        }
    }

    private var claimChangeMessage: String {
        let names = editingSplit.map { draft.claimImpact(comparedTo: $0).itemNamesRequiringConfirmation } ?? []
        let summary = names.isEmpty ? "the changed or removed items" : names.joined(separator: ", ")
        return summary + " already have claims. Saving these financial changes will clear only those claims so everyone can claim the corrected bill again. Cancel keeps the current draft and claims."
    }

    private func submitEdit(clearClaimsFor: Set<String>) {
        guard let editingSplit else { return }
        normalizeCardPaymentState()
        let bodyDraft = submissionDraft
        guard network.isOnline else {
            errorMessage = "Editing needs an internet connection."
            return
        }
        guard let openedEditVersion else {
            errorMessage = "Reload this split before editing."
            return
        }
        errorMessage = nil
        isSubmitting = true
        Task {
            defer { isSubmitting = false }
            let saved = await vm.updateDraft(
                workspaceId: workspaceId,
                splitId: editingSplit.id,
                body: bodyDraft.makeEditBody(version: openedEditVersion, clearClaimsFor: clearClaimsFor)
            )
            if saved, let updated = vm.detail {
                onSaved(.created(updated))
                if dismissOnSave { dismiss() }
            } else {
                errorMessage = vm.errorMessage
            }
        }
    }
}

import SwiftUI

/// Turns a receipt into a split: scan it (or type it), correct the items, and
/// confirm the total. Scanning is a shortcut, never a source of truth — every
/// field it fills stays editable, because a misread price becomes real money
/// somebody is asked to pay back.
struct SplitCreateSheet: View {
    let workspaceId: String
    let vm: BillSplitVM
    /// Items already read off a receipt by the scan flow, if the user came that way.
    var prefill: ScannedReceipt?
    /// Seeded by the caller when the scan couldn't run at all, so an empty form
    /// arrives with an explanation rather than as a mystery.
    var notice: String?
    /// Non-nil uses this same form as the complete, versioned split editor.
    var editingSplit: BillSplit? = nil
    let onSaved: (SplitSaveOutcome) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    private let queue = PendingSplitQueue.shared
    private let network = NetworkMonitor.shared

    @State private var draft = SplitDraft()
    /// Set once the user edits the total by hand; until then it tracks the items.
    @State private var totalEdited = false
    @State private var creditCards: [CreditCard] = []
    @State private var showScanner = false
    @State private var isScanning = false
    @State private var hasScanned = false
    @State private var scanNotice: String?
    @State private var scanNeedsReview = false
    @State private var showReceiptSettings = false
    @State private var errorMessage: String?
    @State private var showKeepMismatchConfirmation = false
    @State private var showClaimChangeConfirmation = false
    @State private var pendingClaimClearIDs: Set<String> = []
    @State private var hasInitialized = false
    /// Captured when the editor opens. The detail view keeps refreshing behind
    /// this sheet, but a newer DTO must not silently lend its version to an
    /// older draft and bypass the server's stale-edit protection.
    @State private var openedEditVersion: Int?
    /// Local rather than `vm.isSaving`: saving now means writing to disk and
    /// then trying the network, which the view model doesn't run.
    @State private var isSubmitting = false
    @FocusState private var merchantFocused: Bool
    /// Every numeric field on the sheet. The decimal pad has no return key, so
    /// tracking focus is the only way to give the user a way out of it.
    @FocusState private var focusedField: Field?

    /// Item rows come and go, so they key off the row's identity, not an index.
    private enum Field: Hashable {
        case itemName(UUID)
        case itemPrice(UUID)
        case guestName(Int)
        case tax
        case tip
        case fee
        case total
    }

    private var filledItems: [SplitDraft.Item] { draft.filledItems }
    private var subtotalCents: Int { draft.itemSubtotalCents }
    private var derivedTotalCents: Int { draft.calculatedTotalCents }
    private var effectiveTotalCents: Int {
        totalEdited ? draft.selectedTotalCents : derivedTotalCents
    }
    private var isEvenSplit: Bool { draft.splitMode == "even" }
    private var isEditing: Bool { editingSplit != nil }
    private var headcount: Int { draft.participants.count }

    private var submissionDraft: SplitDraft {
        var result = draft
        if !totalEdited { result.selectedTotalCents = result.calculatedTotalCents }
        return result
    }

    private var reconciliation: SplitDraft.Reconciliation { submissionDraft.reconciliation }

    private var canSave: Bool {
        // An even split needs a total and a headcount, nothing else — itemising
        // is the work it exists to skip. Every other mode needs priced lines,
        // because there is nothing to claim without them.
        let itemsOk = isEvenSplit || (!filledItems.isEmpty && filledItems.allSatisfy { $0.unitPriceCents > 0 })
        return !draft.merchant.trimmingCharacters(in: .whitespaces).isEmpty
            && itemsOk
            && effectiveTotalCents > 0
            && BillSplitPayerMode(persistedValue: draft.payer) != .unavailable
            && (draft.paymentChannel != "credit_card" || draft.creditCardId != nil)
            && !reconciliation.requiresDecision
            && (!isEditing || network.isOnline)
    }

    /// What one person pays on an even split, shown live so the table can settle
    /// up before the form is even submitted.
    private var evenShareCents: Int {
        guard headcount > 0 else { return 0 }
        return effectiveTotalCents / headcount
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        scanBanner
                        FormCard {
                            FormTextRow(
                                label: "Where",
                                placeholder: "Restaurant or store",
                                text: $draft.merchant,
                                focus: $merchantFocused
                            )
                            FormRowDivider()
                            dateRow
                        }
                        splitModeSection
                        if !isEvenSplit { itemsSection }
                        extrasSection
                        paymentSection

                        if isEditing && !network.isOnline {
                            Text("Editing needs an internet connection. Your existing split has not changed.")
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.warning)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 4)
                        }

                        if let errorMessage {
                            Text(errorMessage)
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.expense)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 4)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 32)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle(isEditing ? "Edit Bill Split" : "Split a Bill")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Theme.muted)
                }
                ToolbarItem(placement: .confirmationAction) {
                    // Says what will actually happen. Offline the split is saved
                    // to the phone and uploads itself later, and promising
                    // "Create" would be a promise this can't keep at a table.
                    Button(saveButtonTitle) { save() }
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(canSave ? Theme.accent : Theme.faint)
                        .disabled(!canSave || isSubmitting)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { dismissKeyboard() }
                        .foregroundStyle(Theme.accent)
                        .fontWeight(.semibold)
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
            .sheet(isPresented: $showReceiptSettings) {
                SettingsView()
            }
            .alert("Keep the receipt total?", isPresented: $showKeepMismatchConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Keep receipt total") { draft.confirmKeepReceiptTotal() }
            } message: {
                Text("The item lines and total differ materially. Keep this total only after checking the receipt for missing or duplicated rows.")
            }
            .alert("Clear existing claims?", isPresented: $showClaimChangeConfirmation) {
                Button("Cancel", role: .cancel) {
                    pendingClaimClearIDs = []
                }
                Button("Save and clear claims", role: .destructive) {
                    let ids = pendingClaimClearIDs
                    pendingClaimClearIDs = []
                    submitEdit(clearClaimsFor: ids)
                }
            } message: {
                Text(claimChangeMessage)
            }
        }
        .preferredColorScheme(.dark)
        .task { await loadCards() }
        .onAppear { applyInitialDraftOnce() }
    }

    private var saveButtonTitle: String {
        if isEditing { return "Save" }
        return network.isOnline ? "Create" : "Save for later"
    }

    // MARK: - Scan

    @ViewBuilder
    private var scanBanner: some View {
        VStack(spacing: 10) {
            Button {
                scanNotice = nil
                errorMessage = nil
                showScanner = true
            } label: {
                HStack(spacing: 10) {
                    if isScanning {
                        ProgressView().tint(Theme.bg)
                    } else {
                        Image(systemName: "doc.viewfinder").font(.system(size: 17, weight: .semibold))
                    }
                    Text(isScanning ? "Reading receipt…" : (hasScanned ? "Scan again" : "Scan receipt"))
                        .font(.system(size: 16, weight: .semibold))
                }
                .foregroundStyle(Theme.bg)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Theme.accent)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .disabled(isScanning)

            if let scanNotice {
                Text(scanNotice)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if scanNeedsReview {
                Button("Receipt parsing settings") {
                    showReceiptSettings = true
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func handleCapture(_ image: UIImage) {
        isScanning = true
        errorMessage = nil
        Task {
            defer { isScanning = false }
            do {
                let text = try await Task.detached(priority: .userInitiated) {
                    try ReceiptOCR.recognizeText(in: image)
                }.value
                applyScan(try await vm.scanReceipt(workspaceId: workspaceId, text: text))
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// Fills the form from a scan that already happened in the capture flow.
    /// Guarded because `onAppear` fires again when the camera cover dismisses.
    private func applyInitialDraftOnce() {
        guard !hasInitialized else { return }
        hasInitialized = true
        if scanNotice == nil, let notice { scanNotice = notice }
        if let editingSplit {
            draft = SplitDraft(split: editingSplit)
            openedEditVersion = editingSplit.version
            totalEdited = true
            hasScanned = true
        } else if let prefill {
            applyScan(prefill)
        } else if draft.participants.count == 1 {
            // Preserve the existing two-person starting point without baking a
            // UI preference into the reusable draft model.
            draft.participants.append(.init(id: nil, name: "", isOrganizer: false))
        }
    }

    private func applyScan(_ parsed: ScannedReceipt) {
        hasScanned = true
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
        // A printed total the lines don't reconstruct is normal (service charge,
        // rounding). Keep it: the server shares the difference across the table.
        if parsed.totalCents > 0 {
            draft.selectedTotalCents = parsed.totalCents
            totalEdited = true
        } else {
            draft.selectedTotalCents = draft.calculatedTotalCents
            totalEdited = false
        }

        let unverifiedCount = parsed.items.filter { $0.verification == .unverified }.count
        scanNeedsReview = unverifiedCount > 0 || !parsed.warnings.isEmpty
        var notes = ["Parsed \(parsed.parser.displayName.lowercased()). Check every line before you send this to anyone."]
        if unverifiedCount > 0 {
            notes.append("\(unverifiedCount) item\(unverifiedCount == 1 ? "" : "s") need\(unverifiedCount == 1 ? "s" : "") review.")
        }
        notes.append(contentsOf: parsed.warnings)
        scanNotice = notes.joined(separator: " ")
    }

    // MARK: - How the bill is being split

    /// The two questions that decide everything else: who actually paid, and
    /// whether the table wants to itemise. Both are asked here rather than after
    /// the fact because they change what the ledger records, and because at a
    /// table the answer is known before anybody starts tapping.
    private var splitModeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionEyebrow("Splitting this bill")
            SegmentedToggle(
                selection: $draft.payer,
                options: [
                    ToggleOption(value: "me", label: "I paid it all", icon: "person.fill"),
                    ToggleOption(value: "each_own", label: "Each paid their own", icon: "person.2.fill"),
                ]
            )
            SegmentedToggle(
                selection: $draft.splitMode,
                options: [
                    ToggleOption(value: "by_item", label: "By item", icon: "list.bullet"),
                    ToggleOption(value: "even", label: "Even", icon: "equal"),
                ]
            )

            FormCard {
                HStack {
                    Text("How many people")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.ink)
                    Spacer()
                    Text("\(headcount)")
                        .font(.system(size: 17, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Theme.accent)
                        .frame(minWidth: 32, alignment: .trailing)
                    Stepper("", value: headcountBinding, in: 1...50)
                        .labelsHidden()
                        .fixedSize()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                if isEvenSplit {
                    FormRowDivider()
                    HStack {
                        Text("Each pays")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                        Spacer()
                        Text(formatSplitMoney(evenShareCents))
                            .font(.system(size: 20, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Theme.accent)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                }
            }
            guestNamesCard

            Text(splitModeExplanation)
                .font(.system(size: 12))
                .foregroundStyle(Theme.faint)
                .padding(.horizontal, 4)
        }
    }

    /// Optional names for the rest of the table.
    ///
    /// Left blank they become "Person 2", "Person 3" — the whole point of an even
    /// split is not having to type anything. But a split you'll still be looking
    /// at tomorrow is worth names, and typing one or two of them shouldn't mean
    /// typing all of them, so every field here stands on its own.
    @ViewBuilder
    private var guestNamesCard: some View {
        if headcount > 1 {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Who's at the table?")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.muted)
                    Text("optional")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.faint)
                }
                .padding(.horizontal, 4)

                FormCard {
                    ForEach(0..<(headcount - 1), id: \.self) { index in
                        if index > 0 { FormRowDivider() }
                        HStack(spacing: 10) {
                            Text("\(index + 2)")
                                .font(.system(size: 13, design: .monospaced))
                                .foregroundStyle(Theme.faint)
                                .frame(width: 18, alignment: .leading)
                            TextField(
                                "",
                                text: guestNameBinding(index),
                                prompt: Text("Person \(index + 2)").foregroundStyle(Theme.faint)
                            )
                            .font(.system(size: 15))
                            .foregroundStyle(Theme.ink)
                            .focused($focusedField, equals: .guestName(index))
                            .submitLabel(.next)
                            .autocorrectionDisabled()
                            .onSubmit {
                                focusedField = index + 1 < headcount - 1
                                    ? .guestName(index + 1)
                                    : nil
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                    }
                }
            }
        }
    }

    /// Reads and writes a sparse array, growing it only when something is typed,
    /// so lowering the headcount and raising it again keeps the earlier names.
    private func guestNameBinding(_ index: Int) -> Binding<String> {
        Binding(
            get: {
                let guests = draft.participants.indices.filter { !draft.participants[$0].isOrganizer }
                guard index < guests.count else { return "" }
                return draft.participants[guests[index]].name
            },
            set: { newValue in
                let guests = draft.participants.indices.filter { !draft.participants[$0].isOrganizer }
                guard index < guests.count else { return }
                draft.participants[guests[index]].name = newValue
            }
        )
    }

    private var headcountBinding: Binding<Int> {
        Binding(
            get: { headcount },
            set: { newCount in
                while draft.participants.count < newCount {
                    draft.participants.append(.init(id: nil, name: "", isOrganizer: false))
                }
                while draft.participants.count > newCount,
                      let lastGuest = draft.participants.lastIndex(where: { !$0.isOrganizer }) {
                    draft.participants.remove(at: lastGuest)
                }
            }
        )
    }

    /// Says what this combination will do to the ledger, in the same words the
    /// ledger will end up using. Getting this wrong is somebody's money.
    private var splitModeExplanation: String {
        switch BillSplitPayerMode(persistedValue: draft.payer) {
        case .eachOwn:
            return isEvenSplit
                ? "Everyone pays the restaurant directly. Only your own share is recorded as your expense, with no reimbursements."
                : "Everyone pays the restaurant directly. Tap the items you had; only your own share is recorded as your expense."
        case .unavailable:
            return "Choose who paid before saving. This decides whether the split records reimbursements or individual shares."
        case .organizerPaid:
            return isEvenSplit
                ? "The full bill is recorded as one expense. Each person you mark as paid back is recorded as income."
                : "The full bill is recorded as one expense. People claim what they ordered, and each one you mark as paid back is recorded as income."
        }
    }

    // MARK: - Items

    private var itemsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionEyebrow("Items")
                Spacer()
                Text(formatSplitMoney(subtotalCents))
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(Theme.muted)
            }

            FormCard {
                ForEach($draft.items) { $item in
                    if item.id != draft.items.first?.id { FormRowDivider() }
                    itemRow($item)
                }
            }

            Button {
                draft.items.append(SplitDraft.Item())
            } label: {
                Label("Add item", systemImage: "plus")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.accent)
            }
            .padding(.leading, 4)
        }
    }

    private func itemRow(_ item: Binding<SplitDraft.Item>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                TextField("", text: item.name, prompt: Text("Item").foregroundStyle(Theme.faint))
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.ink)
                    .focused($focusedField, equals: .itemName(item.wrappedValue.id))
                    .frame(maxWidth: .infinity, alignment: .leading)

                Menu {
                    ForEach(1...20, id: \.self) { n in
                        Button("\(n)×") {
                            guard n != item.wrappedValue.quantity else { return }
                            item.wrappedValue.quantity = n
                            draft.mismatchAcknowledged = false
                        }
                    }
                } label: {
                    Text("\(item.wrappedValue.quantity)×")
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(item.wrappedValue.quantity > 1 ? Theme.accent : Theme.faint)
                        .frame(width: 34)
                }

                TextField(
                    "",
                    text: itemPriceBinding(item.wrappedValue.id),
                    prompt: Text("0.00").foregroundStyle(Theme.faint)
                )
                    .font(.system(size: 15, design: .monospaced))
                    .foregroundStyle(Theme.ink)
                    .keyboardType(.decimalPad)
                    .focused($focusedField, equals: .itemPrice(item.wrappedValue.id))
                    .multilineTextAlignment(.trailing)
                    .frame(width: 88)

                Button {
                    withAnimation(.easeOut(duration: 0.15)) {
                        draft.items.removeAll { $0.id == item.wrappedValue.id }
                        if draft.items.isEmpty { draft.items = [SplitDraft.Item()] }
                        draft.mismatchAcknowledged = false
                    }
                } label: {
                    Image(systemName: "minus.circle")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.faint)
                }
            }
            Menu {
                Button("Claim individual units") {
                    guard item.wrappedValue.allocationMode != "units" else { return }
                    item.wrappedValue.allocationMode = "units"
                }
                Button("Share the whole item") {
                    guard item.wrappedValue.allocationMode != "shared" else { return }
                    item.wrappedValue.allocationMode = "shared"
                }
            } label: {
                Label(
                    item.wrappedValue.allocationMode == "units" ? "Individual units" : "Shared item",
                    systemImage: item.wrappedValue.allocationMode == "units" ? "square.stack.3d.up" : "person.2"
                )
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.muted)
            }
            if item.wrappedValue.verification == .unverified {
                Label("Unverified receipt row — check its name, quantity, and price", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.warning)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func itemPriceBinding(_ id: UUID) -> Binding<String> {
        Binding(
            get: {
                guard let item = draft.items.first(where: { $0.id == id }) else { return "" }
                return item.unitPriceCents > 0 ? textFromCents(item.unitPriceCents) : ""
            },
            set: { value in
                guard let index = draft.items.firstIndex(where: { $0.id == id }) else { return }
                let newValue = centsFromText(value)
                if draft.items[index].unitPriceCents != newValue {
                    draft.items[index].unitPriceCents = newValue
                    draft.mismatchAcknowledged = false
                }
            }
        )
    }

    // MARK: - Extras + total

    private var extrasSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionEyebrow("Tax, tip & total")
            FormCard {
                moneyRow(label: "Tax", text: moneyBinding(\.taxCents), field: .tax)
                FormRowDivider()
                moneyRow(label: "Tip", text: moneyBinding(\.tipCents), field: .tip)
                if tipBaseCents > 0 {
                    tipShortcuts
                }
                FormRowDivider()
                moneyRow(label: "Fee", text: moneyBinding(\.feeCents), field: .fee)
                FormRowDivider()
                HStack {
                    Text("Total")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                    Spacer()
                    TextField(
                        "",
                        text: Binding(
                            get: {
                                totalEdited
                                    ? textFromCents(draft.selectedTotalCents)
                                    : textFromCents(derivedTotalCents)
                            },
                            set: {
                                draft.selectedTotalCents = centsFromText($0)
                                draft.mismatchAcknowledged = false
                                totalEdited = true
                            }
                        ),
                        prompt: Text("0.00").foregroundStyle(Theme.faint)
                    )
                    .font(.system(size: 17, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.accent)
                    .keyboardType(.decimalPad)
                    .focused($focusedField, equals: .total)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 120)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }

            if totalEdited, effectiveTotalCents != derivedTotalCents {
                Text(totalMismatchNote)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
                    .padding(.horizontal, 4)
            }
            reconciliationReview
        }
    }

    @ViewBuilder
    private var reconciliationReview: some View {
        if reconciliation.isMaterial {
            VStack(alignment: .leading, spacing: 10) {
                SectionEyebrow("Check the receipt")
                FormCard {
                    reconciliationRow("Item subtotal", reconciliation.itemSubtotalCents)
                    FormRowDivider()
                    reconciliationRow("Calculated total", reconciliation.calculatedTotalCents)
                    FormRowDivider()
                    reconciliationRow("Receipt total", reconciliation.selectedTotalCents)
                    FormRowDivider()
                    reconciliationRow("Difference", reconciliation.differenceCents, signed: true)
                }

                if !draft.unverifiedItems.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Unverified rows")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.warning)
                        ForEach(draft.unverifiedItems) { item in
                            Text("• \(item.name)")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.muted)
                        }
                    }
                    .padding(.horizontal, 4)
                }

                HStack(spacing: 10) {
                    Button("Keep receipt total") { showKeepMismatchConfirmation = true }
                        .buttonStyle(.bordered)
                        .tint(draft.mismatchAcknowledged ? Theme.income : Theme.warning)
                    Button("Use calculated total") {
                        draft.useCalculatedTotal()
                        totalEdited = true
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                }
                .font(.system(size: 13, weight: .semibold))

                if draft.mismatchAcknowledged {
                    Text("Receipt total confirmed.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.income)
                }
            }
        }
    }

    private func reconciliationRow(_ label: String, _ cents: Int, signed: Bool = false) -> some View {
        HStack {
            Text(label).foregroundStyle(Theme.muted)
            Spacer()
            Text(signed && cents > 0 ? "+\(formatSplitMoney(cents))" : formatSplitMoney(cents))
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(signed ? Theme.warning : Theme.ink)
        }
        .font(.system(size: 13))
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Tip shortcuts

    /// Most receipts here print a suggested tip that isn't part of the total, or
    /// print none at all — and `ReceiptReconciler` deliberately strips a printed
    /// `PROPINA SUGERIDA` back out, because it was a suggestion nobody was
    /// billed for. That leaves the organizer doing percentage arithmetic at a
    /// table, which is the one moment they have least patience for it.
    private var tipShortcuts: some View {
        HStack(spacing: 8) {
            ForEach(TipPreset.values, id: \.self) { percent in
                tipChip(percent)
            }
            Spacer(minLength: 0)
            Text(formatSplitMoney(tipBaseCents))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Theme.faint)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 11)
    }

    private func tipChip(_ percent: Int) -> some View {
        let isActive = activeTipPercent == percent
        return Button {
            // Tapping the active one clears it — the obvious way to undo, and
            // otherwise there's no route back to no tip except the keyboard.
            applyTip(percent: isActive ? nil : percent)
        } label: {
            Text("\(percent)%")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isActive ? Theme.bg : Theme.muted)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isActive ? Theme.accent : Theme.surface2)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    /// What the percentage is taken on: the bill before any tip.
    ///
    /// Mexican prices already include IVA, so after reconciliation `taxCents` is
    /// usually zero and this is simply the items — which is what a `propina` is
    /// customarily figured on. On a receipt that really does add tax on top,
    /// including it gives the post-tax base instead. Falls back to the typed
    /// total for an even split, where there are no lines to add up.
    private var tipBaseCents: Int {
        if subtotalCents > 0 { return subtotalCents + draft.taxCents }
        return max(0, effectiveTotalCents - draft.tipCents)
    }

    /// The percentage currently in the tip field, if it is one of the presets.
    private var activeTipPercent: Int? {
        TipPreset.activePercent(base: tipBaseCents, tipCents: draft.tipCents)
    }

    private func tipCents(percent: Int) -> Int {
        TipPreset.cents(base: tipBaseCents, percent: percent)
    }

    /// Sets the tip, and moves the total with it.
    ///
    /// A scanned receipt sets the total by hand (`totalEdited`), and from then
    /// on the total stops tracking the lines. Without adjusting it here, adding
    /// a tip would leave the total untouched — the tip would be swallowed, the
    /// mismatch warning would fire, and the table would under-pay by exactly the
    /// tip. Swapping the old tip out and the new one in also makes 10% → 15%
    /// mean what it looks like rather than compounding.
    private func applyTip(percent: Int?) {
        let newTip = percent.map { tipCents(percent: $0) } ?? 0
        if totalEdited {
            draft.selectedTotalCents = TipPreset.retotal(
                selectedTotal: draft.selectedTotalCents,
                replacing: draft.tipCents,
                with: newTip
            )
        }
        draft.tipCents = newTip
        draft.mismatchAcknowledged = false
    }

    /// The lines and the total disagreeing is worth saying plainly, and the two
    /// directions need different fixes: short means a line was missed, over means
    /// one was counted twice.
    private var totalMismatchNote: String {
        let gap = abs(effectiveTotalCents - derivedTotalCents)
        if effectiveTotalCents > derivedTotalCents {
            return "\(formatSplitMoney(gap)) of the total isn't in the lines above — check whether the scan missed a line. Whatever is left over is shared across the table in proportion to what everyone ordered."
        }
        return "The lines above add up to \(formatSplitMoney(gap)) more than the total. Check for a line that was counted twice."
    }

    private func moneyRow(label: String, text: Binding<String>, field: Field) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 15))
                .foregroundStyle(Theme.ink)
            Spacer()
            TextField("", text: text, prompt: Text("0.00").foregroundStyle(Theme.faint))
                .font(.system(size: 15, design: .monospaced))
                .foregroundStyle(Theme.ink)
                .keyboardType(.decimalPad)
                .focused($focusedField, equals: field)
                .multilineTextAlignment(.trailing)
                .frame(width: 110)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private func moneyBinding(_ keyPath: WritableKeyPath<SplitDraft, Int>) -> Binding<String> {
        Binding(
            get: {
                let cents = draft[keyPath: keyPath]
                return cents > 0 ? textFromCents(cents) : ""
            },
            set: {
                draft[keyPath: keyPath] = centsFromText($0)
                draft.mismatchAcknowledged = false
            }
        )
    }

    // MARK: - Payment

    private var paymentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionEyebrow("You paid with")
            SegmentedToggle(
                selection: $draft.paymentChannel,
                options: [
                    ToggleOption(value: "cash", label: "Cash / debit", icon: "banknote"),
                    ToggleOption(value: "credit_card", label: "Credit card", icon: "creditcard"),
                ]
            )
            if draft.paymentChannel == "credit_card" {
                FormCard {
                    FormMenuRow(
                        label: "Card",
                        value: creditCards.first { $0.id == draft.creditCardId }?.label ?? "Select"
                    ) {
                        ForEach(creditCards) { card in
                            Button(card.label) { draft.creditCardId = card.id }
                        }
                    }
                }
            }
        }
    }

    private var dateRow: some View {
        HStack {
            Text("Date")
                .font(.system(size: 15))
                .foregroundStyle(Theme.ink)
            Spacer()
            DatePicker("", selection: $draft.occurredAt, displayedComponents: .date)
                .labelsHidden()
                .colorScheme(.dark)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    // MARK: - Actions

    private func dismissKeyboard() {
        merchantFocused = false
        focusedField = nil
    }

    /// Cache first, network second.
    ///
    /// Without the cached list an offline split can only ever be recorded as
    /// cash — `canSave` blocks "credit card" until a card is picked — and that
    /// is a wrong ledger row, not a cosmetic gap: `paymentChannel` and
    /// `creditCardId` decide what the expense the server writes looks like.
    private func loadCards() async {
        creditCards = OfflineSessionCache.creditCards(workspaceId: workspaceId)
            .filter { !$0.isArchived }
        guard let resp: CreditCardsResponse = try? await APIClient.shared.fetch(
            Endpoints.creditCards(workspaceId)
        ) else { return }
        OfflineSessionCache.saveCreditCards(resp.creditCards, workspaceId: workspaceId)
        creditCards = resp.creditCards.filter { !$0.isArchived }
    }

    private func save() {
        let bodyDraft = submissionDraft
        if bodyDraft.reconciliation.requiresDecision {
            errorMessage = "Choose whether to keep the receipt total or use the calculated total."
            return
        }

        if let editingSplit {
            guard network.isOnline else {
                errorMessage = "Editing needs an internet connection."
                return
            }
            guard let openedEditVersion else {
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
            // Written to disk before a single byte goes out, so a split can't be
            // lost to a dropped connection or to the app being killed
            // mid-request. Online, it usually comes straight back as `.created`.
            let entry = queue.makeEntry(userId: userId, workspaceId: workspaceId, body: body)
            let outcome = await queue.save(entry)
            switch outcome {
            case .created, .queued:
                onSaved(outcome)
                dismiss()
            case .rejected(let message):
                // The server looked at this and said no. Stay open with every
                // field intact so it can be fixed — exactly as before.
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
                dismiss()
            } else {
                errorMessage = vm.errorMessage
            }
        }
    }

}

// MARK: - Money text helpers

/// "12.50" → 1250. Tolerates a comma decimal separator and stray currency text.
func centsFromText(_ raw: String) -> Int {
    let cleaned = raw.replacingOccurrences(of: ",", with: ".")
        .filter { $0.isNumber || $0 == "." }
    guard let value = Double(cleaned) else { return 0 }
    return Int((value * 100).rounded())
}

func textFromCents(_ cents: Int) -> String {
    String(format: "%.2f", Double(cents) / 100.0)
}

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
    let onSaved: (SplitSaveOutcome) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    private let queue = PendingSplitQueue.shared
    private let network = NetworkMonitor.shared

    @State private var merchant = ""
    @State private var occurredAt = Date()
    @State private var items: [DraftItem] = [DraftItem()]
    @State private var taxText = ""
    @State private var tipText = ""
    @State private var totalText = ""
    /// Set once the user edits the total by hand; until then it tracks the items.
    @State private var totalEdited = false
    @State private var paymentChannel = "cash"
    /// "me" — you fronted the bill and the table owes you back.
    /// "each_own" — everyone paid their own share, so nothing is owed.
    @State private var payer = "me"
    /// "by_item" — people claim what they ordered. "even" — divide by heads.
    @State private var splitMode = "by_item"
    @State private var headcount = 2
    /// Names for the other people on an even split, you excluded, indexed from
    /// person 2. Kept sparse on purpose: naming anybody is optional, and lowering
    /// the headcount then raising it again shouldn't lose what was typed.
    @State private var guestNames: [String] = []
    @State private var creditCards: [CreditCard] = []
    @State private var selectedCreditCardId: String?
    @State private var showScanner = false
    @State private var isScanning = false
    @State private var hasScanned = false
    @State private var scanNotice: String?
    @State private var errorMessage: String?
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
        case total
    }

    struct DraftItem: Identifiable {
        let id = UUID()
        var name = ""
        var quantity = 1
        var priceText = ""

        var unitPriceCents: Int { centsFromText(priceText) }
        var lineTotalCents: Int { unitPriceCents * max(0, quantity) }
        var isBlank: Bool {
            name.trimmingCharacters(in: .whitespaces).isEmpty && priceText.isEmpty
        }
    }

    private var filledItems: [DraftItem] { items.filter { !$0.isBlank } }
    private var subtotalCents: Int { filledItems.reduce(0) { $0 + $1.lineTotalCents } }
    private var derivedTotalCents: Int {
        subtotalCents + centsFromText(taxText) + centsFromText(tipText)
    }
    private var effectiveTotalCents: Int {
        totalEdited ? centsFromText(totalText) : derivedTotalCents
    }
    private var isEvenSplit: Bool { splitMode == "even" }

    private var canSave: Bool {
        // An even split needs a total and a headcount, nothing else — itemising
        // is the work it exists to skip. Every other mode needs priced lines,
        // because there is nothing to claim without them.
        let itemsOk = isEvenSplit || (!filledItems.isEmpty && filledItems.allSatisfy { $0.unitPriceCents > 0 })
        return !merchant.trimmingCharacters(in: .whitespaces).isEmpty
            && itemsOk
            && effectiveTotalCents > 0
            && (paymentChannel != "credit_card" || selectedCreditCardId != nil)
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
                                text: $merchant,
                                focus: $merchantFocused
                            )
                            FormRowDivider()
                            dateRow
                        }
                        splitModeSection
                        if !isEvenSplit { itemsSection }
                        extrasSection
                        paymentSection

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
            .navigationTitle("Split a Bill")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Theme.muted)
                }
                ToolbarItem(placement: .confirmationAction) {
                    // Says what will actually happen. Offline the split is saved
                    // to the phone and uploads itself later, and promising
                    // "Create" would be a promise this can't keep at a table.
                    Button(network.isOnline ? "Create" : "Save for later") { save() }
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
        }
        .preferredColorScheme(.dark)
        .task { await loadCards() }
        .onAppear { applyPrefillOnce() }
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
    private func applyPrefillOnce() {
        if scanNotice == nil, let notice { scanNotice = notice }
        guard let prefill, !hasScanned else { return }
        applyScan(prefill)
    }

    private func applyScan(_ parsed: ScannedReceipt) {
        hasScanned = true
        if merchant.trimmingCharacters(in: .whitespaces).isEmpty, let scanned = parsed.merchant {
            merchant = scanned
        }
        items = parsed.items.map {
            DraftItem(name: $0.name, quantity: max(1, $0.quantity), priceText: textFromCents($0.unitPriceCents))
        }
        items.append(DraftItem())
        if parsed.taxCents > 0 { taxText = textFromCents(parsed.taxCents) }
        if parsed.tipCents > 0 { tipText = textFromCents(parsed.tipCents) }
        // A printed total the lines don't reconstruct is normal (service charge,
        // rounding). Keep it: the server shares the difference across the table.
        if parsed.totalCents > 0 {
            totalText = textFromCents(parsed.totalCents)
            totalEdited = true
        }

        var notes = ["Check every line before you send this to anyone."]
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
                selection: $payer,
                options: [
                    ToggleOption(value: "me", label: "I paid it all", icon: "person.fill"),
                    ToggleOption(value: "each_own", label: "Each paid their own", icon: "person.2.fill"),
                ]
            )
            SegmentedToggle(
                selection: $splitMode,
                options: [
                    ToggleOption(value: "by_item", label: "By item", icon: "list.bullet"),
                    ToggleOption(value: "even", label: "Even", icon: "equal"),
                ]
            )

            if isEvenSplit {
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
                        Stepper("", value: $headcount, in: 1...50)
                            .labelsHidden()
                            .fixedSize()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
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

                guestNamesCard
            }

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
                    Text("Who else")
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
            get: { index < guestNames.count ? guestNames[index] : "" },
            set: { newValue in
                if guestNames.count <= index {
                    guestNames.append(contentsOf: Array(repeating: "", count: index - guestNames.count + 1))
                }
                guestNames[index] = newValue
            }
        )
    }

    /// Says what this combination will do to the ledger, in the same words the
    /// ledger will end up using. Getting this wrong is somebody's money.
    private var splitModeExplanation: String {
        if payer == "each_own" {
            return isEvenSplit
                ? "Everyone pays the restaurant directly. Only your own share is recorded as your expense, and nobody owes you anything."
                : "Everyone pays the restaurant directly. Tap the items you had; only your own share is recorded as your expense."
        }
        return isEvenSplit
            ? "The full bill is recorded as one expense. Each person you mark as paid back is recorded as income."
            : "The full bill is recorded as one expense. People claim what they ordered, and each one you mark as paid back is recorded as income."
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
                ForEach($items) { $item in
                    if item.id != items.first?.id { FormRowDivider() }
                    itemRow($item)
                }
            }

            Button {
                items.append(DraftItem())
            } label: {
                Label("Add item", systemImage: "plus")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.accent)
            }
            .padding(.leading, 4)
        }
    }

    private func itemRow(_ item: Binding<DraftItem>) -> some View {
        HStack(spacing: 10) {
            TextField("", text: item.name, prompt: Text("Item").foregroundStyle(Theme.faint))
                .font(.system(size: 15))
                .foregroundStyle(Theme.ink)
                .focused($focusedField, equals: .itemName(item.wrappedValue.id))
                .frame(maxWidth: .infinity, alignment: .leading)

            Menu {
                ForEach(1...20, id: \.self) { n in
                    Button("\(n)×") { item.wrappedValue.quantity = n }
                }
            } label: {
                Text("\(item.wrappedValue.quantity)×")
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(item.wrappedValue.quantity > 1 ? Theme.accent : Theme.faint)
                    .frame(width: 34)
            }

            TextField("", text: item.priceText, prompt: Text("0.00").foregroundStyle(Theme.faint))
                .font(.system(size: 15, design: .monospaced))
                .foregroundStyle(Theme.ink)
                .keyboardType(.decimalPad)
                .focused($focusedField, equals: .itemPrice(item.wrappedValue.id))
                .multilineTextAlignment(.trailing)
                .frame(width: 88)

            Button {
                withAnimation(.easeOut(duration: 0.15)) {
                    items.removeAll { $0.id == item.wrappedValue.id }
                    if items.isEmpty { items = [DraftItem()] }
                }
            } label: {
                Image(systemName: "minus.circle")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.faint)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Extras + total

    private var extrasSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionEyebrow("Tax, tip & total")
            FormCard {
                moneyRow(label: "Tax", text: $taxText, field: .tax)
                FormRowDivider()
                moneyRow(label: "Tip", text: $tipText, field: .tip)
                if tipBaseCents > 0 {
                    tipShortcuts
                }
                FormRowDivider()
                HStack {
                    Text("Total")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                    Spacer()
                    TextField(
                        "",
                        text: Binding(
                            get: { totalEdited ? totalText : textFromCents(derivedTotalCents) },
                            set: { totalText = $0; totalEdited = true }
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
        }
    }

    // MARK: - Tip shortcuts

    /// Most receipts here print a suggested tip that isn't part of the total, or
    /// print none at all — and `ReceiptReconciler` deliberately strips a printed
    /// `PROPINA SUGERIDA` back out, because it was a suggestion nobody was
    /// billed for. That leaves the organizer doing percentage arithmetic at a
    /// table, which is the one moment they have least patience for it.
    private var tipShortcuts: some View {
        HStack(spacing: 8) {
            ForEach([10, 15, 20], id: \.self) { percent in
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
        if subtotalCents > 0 { return subtotalCents + centsFromText(taxText) }
        return max(0, effectiveTotalCents - centsFromText(tipText))
    }

    /// The percentage currently in the tip field, if it is one of the presets.
    private var activeTipPercent: Int? {
        let tip = centsFromText(tipText)
        guard tip > 0, tipBaseCents > 0 else { return nil }
        return [10, 15, 20].first { tipCents(percent: $0) == tip }
    }

    private func tipCents(percent: Int) -> Int {
        TipMath.cents(base: tipBaseCents, percent: percent)
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
            totalText = textFromCents(
                TipMath.retotal(
                    total: centsFromText(totalText),
                    replacing: centsFromText(tipText),
                    with: newTip
                )
            )
        }
        tipText = newTip > 0 ? textFromCents(newTip) : ""
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

    // MARK: - Payment

    private var paymentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionEyebrow("You paid with")
            SegmentedToggle(
                selection: $paymentChannel,
                options: [
                    ToggleOption(value: "cash", label: "Cash / debit", icon: "banknote"),
                    ToggleOption(value: "credit_card", label: "Credit card", icon: "creditcard"),
                ]
            )
            if paymentChannel == "credit_card" {
                FormCard {
                    FormMenuRow(
                        label: "Card",
                        value: creditCards.first { $0.id == selectedCreditCardId }?.label ?? "Select"
                    ) {
                        ForEach(creditCards) { card in
                            Button(card.label) { selectedCreditCardId = card.id }
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
            DatePicker("", selection: $occurredAt, displayedComponents: .date)
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
        guard let userId = appState.currentUser?.id else {
            errorMessage = "Sign in again to save this split."
            return
        }
        errorMessage = nil
        isSubmitting = true
        let body = CreateBillSplitBody(
            merchant: merchant.trimmingCharacters(in: .whitespaces),
            occurredAt: isoDay(occurredAt),
            // An even split keeps whatever was scanned — the lines are still worth
            // having on the record — but the shares come from the headcount.
            items: filledItems.map {
                BillSplitItemBody(
                    name: $0.name.trimmingCharacters(in: .whitespaces),
                    quantity: max(1, $0.quantity),
                    unitPriceCents: $0.unitPriceCents
                )
            },
            taxCents: centsFromText(taxText),
            tipCents: centsFromText(tipText),
            feeCents: 0,
            totalCents: effectiveTotalCents,
            paymentChannel: paymentChannel,
            creditCardId: paymentChannel == "credit_card" ? selectedCreditCardId : nil,
            payer: payer,
            splitMode: splitMode,
            participantCount: isEvenSplit ? headcount : nil,
            // Padded to the headcount so a name typed for person 4 doesn't slide
            // onto person 3 when person 2 was left blank.
            participantNames: isEvenSplit && headcount > 1
                ? (0..<(headcount - 1)).map { $0 < guestNames.count ? guestNames[$0] : "" }
                : nil
        )
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

    /// Pinned to a fixed locale and calendar.
    ///
    /// A bare `DateFormatter` follows the device: on a Buddhist-calendar phone
    /// `yyyy-MM-dd` renders 2026 as 2568, and the server would reject it or file
    /// the dinner five centuries out. It mattered less when the value was sent
    /// immediately; now it can sit in the queue for hours first.
    private func isoDay(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
}

// MARK: - Tip arithmetic

/// The two sums behind the tip shortcuts, kept out of the view so they can be
/// exercised on their own. Both produce money somebody is asked to pay back.
enum TipMath {
    /// Rounded to the nearest cent, so 15% of an odd subtotal doesn't leave a
    /// fraction that the share math would then have to redistribute.
    static func cents(base: Int, percent: Int) -> Int {
        guard base > 0, percent > 0 else { return 0 }
        return Int((Double(base) * Double(percent) / 100).rounded())
    }

    /// Swaps one tip out of a total and another in.
    ///
    /// Needed because a scanned receipt pins the total by hand, after which it
    /// stops tracking the lines: adding a tip without moving the total would
    /// leave it swallowed, and the table would under-pay by exactly the tip.
    /// Removing the old tip first is what stops 10% → 15% from compounding.
    static func retotal(total: Int, replacing oldTip: Int, with newTip: Int) -> Int {
        max(0, total - oldTip) + newTip
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

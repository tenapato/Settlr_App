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
    let onCreated: (BillSplit) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var merchant = ""
    @State private var occurredAt = Date()
    @State private var items: [DraftItem] = [DraftItem()]
    @State private var taxText = ""
    @State private var tipText = ""
    @State private var totalText = ""
    /// Set once the user edits the total by hand; until then it tracks the items.
    @State private var totalEdited = false
    @State private var paymentChannel = "cash"
    @State private var creditCards: [CreditCard] = []
    @State private var selectedCreditCardId: String?
    @State private var showScanner = false
    @State private var isScanning = false
    @State private var hasScanned = false
    @State private var scanNotice: String?
    @State private var errorMessage: String?
    @FocusState private var merchantFocused: Bool

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
    private var canSave: Bool {
        !merchant.trimmingCharacters(in: .whitespaces).isEmpty
            && !filledItems.isEmpty
            && filledItems.allSatisfy { $0.unitPriceCents > 0 }
            && effectiveTotalCents > 0
            && (paymentChannel != "credit_card" || selectedCreditCardId != nil)
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
                        itemsSection
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
            }
            .navigationTitle("Split a Bill")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Theme.muted)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { save() }
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(canSave ? Theme.accent : Theme.faint)
                        .disabled(!canSave || vm.isSaving)
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
                moneyRow(label: "Tax", text: $taxText)
                FormRowDivider()
                moneyRow(label: "Tip", text: $tipText)
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
                    .multilineTextAlignment(.trailing)
                    .frame(width: 120)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }

            if totalEdited, effectiveTotalCents > derivedTotalCents {
                Text(
                    "\(formatSplitMoney(effectiveTotalCents - derivedTotalCents)) of the total isn't in the lines above. It gets shared across the table in proportion to what everyone ordered."
                )
                .font(.system(size: 12))
                .foregroundStyle(Theme.muted)
                .padding(.horizontal, 4)
            }
        }
    }

    private func moneyRow(label: String, text: Binding<String>) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 15))
                .foregroundStyle(Theme.ink)
            Spacer()
            TextField("", text: text, prompt: Text("0.00").foregroundStyle(Theme.faint))
                .font(.system(size: 15, design: .monospaced))
                .foregroundStyle(Theme.ink)
                .keyboardType(.decimalPad)
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
            Text("The full bill is recorded as one expense. Each person you mark as paid back is recorded as income.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.faint)
                .padding(.horizontal, 4)
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

    private func loadCards() async {
        guard let resp: CreditCardsResponse = try? await APIClient.shared.fetch(
            Endpoints.creditCards(workspaceId)
        ) else { return }
        creditCards = resp.creditCards.filter { !$0.isArchived }
    }

    private func save() {
        errorMessage = nil
        let body = CreateBillSplitBody(
            merchant: merchant.trimmingCharacters(in: .whitespaces),
            occurredAt: isoDay(occurredAt),
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
            creditCardId: paymentChannel == "credit_card" ? selectedCreditCardId : nil
        )
        Task {
            if let created = await vm.create(workspaceId: workspaceId, body: body) {
                onCreated(created)
                dismiss()
            } else {
                errorMessage = vm.errorMessage
            }
        }
    }

    private func isoDay(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
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

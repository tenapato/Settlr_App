import SwiftUI

/// Sheet-local state deliberately owns the pending choice. A conflict refresh
/// advances only `version`, so the organizer can retry without selecting the
/// same channel and card again.
struct SplitPaymentMethodEditorState: Equatable {
    private(set) var version: Int
    private(set) var paymentChannel: String
    private(set) var creditCardId: String?

    init(version: Int, paymentChannel: String, creditCardId: String?) {
        self.version = version
        self.paymentChannel = paymentChannel
        self.creditCardId = paymentChannel == "credit_card" ? creditCardId : nil
    }

    init(split: BillSplit) {
        self.init(
            version: split.version,
            paymentChannel: split.paymentChannel,
            creditCardId: split.creditCardId
        )
    }

    var canSave: Bool {
        paymentChannel == "cash"
            || (paymentChannel == "credit_card" && creditCardId != nil)
    }

    mutating func selectPaymentChannel(_ channel: String) {
        paymentChannel = channel
        if channel == "cash" { creditCardId = nil }
    }

    mutating func selectCreditCard(_ id: String) {
        paymentChannel = "credit_card"
        creditCardId = id
    }

    mutating func adoptRefreshedVersion(_ version: Int) {
        self.version = version
    }

    func displayValue(cards: [CreditCard]) -> String {
        guard paymentChannel == "credit_card" else { return "Cash / debit" }
        guard let card = cards.first(where: { $0.id == creditCardId }) else {
            return "Credit card"
        }
        guard let lastFour = card.lastFour, !lastFour.isEmpty else { return card.label }
        return "\(card.label) •••• \(lastFour)"
    }

    var requestBody: BillSplitPaymentMethodBody {
        BillSplitPaymentMethodBody(
            version: version,
            paymentChannel: paymentChannel,
            creditCardId: paymentChannel == "credit_card" ? creditCardId : nil
        )
    }
}

struct SplitPaymentMethodSheet: View {
    let workspaceId: String
    let split: BillSplit
    let vm: BillSplitVM
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var state: SplitPaymentMethodEditorState
    @State private var creditCards: [CreditCard] = []

    init(
        workspaceId: String,
        split: BillSplit,
        vm: BillSplitVM,
        onSaved: @escaping () -> Void
    ) {
        self.workspaceId = workspaceId
        self.split = split
        self.vm = vm
        self.onSaved = onSaved
        _state = State(initialValue: SplitPaymentMethodEditorState(split: split))
    }

    private var activeCards: [CreditCard] {
        creditCards.filter { !$0.isArchived }
    }

    private var canSubmit: Bool {
        guard state.canSave, !vm.isSaving else { return false }
        guard state.paymentChannel == "credit_card" else { return true }
        return activeCards.contains { $0.id == state.creditCardId }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()
                VStack(alignment: .leading, spacing: 18) {
                    SegmentedToggle(
                        selection: Binding(
                            get: { state.paymentChannel },
                            set: { state.selectPaymentChannel($0) }
                        ),
                        options: [
                            ToggleOption(value: "cash", label: "Cash / debit", icon: "banknote"),
                            ToggleOption(value: "credit_card", label: "Credit card", icon: "creditcard"),
                        ]
                    )

                    if state.paymentChannel == "credit_card" {
                        FormCard {
                            FormMenuRow(
                                label: "Card",
                                value: state.displayValue(cards: creditCards),
                                isPlaceholder: state.creditCardId == nil
                            ) {
                                ForEach(activeCards) { card in
                                    Button(cardMenuLabel(card)) {
                                        state.selectCreditCard(card.id)
                                    }
                                }
                            }
                        }
                        if activeCards.isEmpty {
                            Text("Add an active card before choosing credit card.")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.faint)
                        }
                    }

                    if let error = vm.errorMessage {
                        Text(error)
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.expense)
                    }

                    Button(vm.isSaving ? "Saving…" : "Save") { save() }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(!canSubmit)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 28)
                .frame(maxHeight: .infinity, alignment: .top)
            }
            .navigationTitle("Payment method")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Theme.muted)
                }
            }
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.medium])
        .task { await loadCards() }
        .onChange(of: vm.detail?.version) { _, refreshedVersion in
            if let refreshedVersion { state.adoptRefreshedVersion(refreshedVersion) }
        }
    }

    private func cardMenuLabel(_ card: CreditCard) -> String {
        guard let lastFour = card.lastFour, !lastFour.isEmpty else { return card.label }
        return "\(card.label) · •••• \(lastFour)"
    }

    @MainActor
    private func loadCards() async {
        creditCards = OfflineSessionCache.creditCards(workspaceId: workspaceId)
        guard let response: CreditCardsResponse = try? await APIClient.shared.fetch(
            Endpoints.creditCards(workspaceId)
        ) else { return }
        OfflineSessionCache.saveCreditCards(response.creditCards, workspaceId: workspaceId)
        creditCards = response.creditCards
    }

    private func save() {
        Task {
            if await vm.updatePaymentMethod(
                workspaceId: workspaceId,
                splitId: split.id,
                body: state.requestBody
            ) {
                onSaved()
            }
        }
    }
}

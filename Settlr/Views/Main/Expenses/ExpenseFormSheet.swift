import SwiftUI

struct ExpenseFormSheet: View {
    let workspaceId: String
    let categories: [Category]
    var expense: Expense?
    var automationDraft: AutomationExpenseDraft?
    var automationWorkspaceName: String?
    var saveAction: ((CreateExpenseBody) async throws -> Void)?
    let onSave: (CreateExpenseBody) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    @State private var description: String
    @State private var amountText: String
    @State private var selectedDate: Date
    @State private var selectedCategoryId: String?
    @State private var paymentChannel: String
    @State private var creditCards: [CreditCard] = []
    @State private var selectedCreditCardId: String?
    @State private var errorMessage: String?
    @State private var isSaving = false
    @State private var cardLoadError: String?
    @State private var splitChoice = ""
    @State private var splitVM = BillSplitVM()
    @State private var selectedSplitId: String?
    @State private var showNewSplit = false
    @State private var splitWasSaved = false

    private var isWalletPayment: Bool { automationDraft?.isWalletPayment == true }
    private var canLinkSplit: Bool {
        automationDraft != nil && (appState.currentUser?.has(.billSplits) ?? false)
    }
    private var selectedSplit: BillSplit? {
        guard let selectedSplitId, splitVM.detail?.id == selectedSplitId else { return nil }
        return splitVM.detail
    }
    @FocusState private var amountFocused: Bool
    @FocusState private var descriptionFocused: Bool

    private var isEditing: Bool { expense != nil }
    private var canUseCreditCards: Bool { appState.currentUser?.has(.creditCards) == true }
    private var effectivePaymentChannel: String { canUseCreditCards ? paymentChannel : "cash" }
    private var effectiveCreditCardId: String? {
        effectivePaymentChannel == "credit_card" ? selectedCreditCardId : nil
    }

    init(
        workspaceId: String,
        categories: [Category],
        expense: Expense? = nil,
        automationDraft: AutomationExpenseDraft? = nil,
        automationWorkspaceName: String? = nil,
        saveAction: ((CreateExpenseBody) async throws -> Void)? = nil,
        onSave: @escaping (CreateExpenseBody) -> Void
    ) {
        self.workspaceId = workspaceId
        self.categories = categories
        self.expense = expense
        self.onSave = onSave
        self.automationDraft = automationDraft
        self.automationWorkspaceName = automationWorkspaceName
        self.saveAction = saveAction

        if let expense {
            _description = State(initialValue: expense.description)
            _amountText = State(initialValue: Self.formatAmount(expense.amountCents))
            _selectedDate = State(initialValue: Self.parseFormDate(expense.occurredAt))
            _selectedCategoryId = State(initialValue: expense.categoryId)
            _paymentChannel = State(initialValue: expense.paymentChannel)
            _selectedCreditCardId = State(initialValue: expense.creditCardId)
        } else {
            _description = State(initialValue: automationDraft?.description ?? "")
            _amountText = State(initialValue: automationDraft?.amountText ?? "")
            _selectedDate = State(initialValue: automationDraft?.createdAt ?? Date())
            _selectedCategoryId = State(initialValue: nil)
            _paymentChannel = State(initialValue: automationDraft?.isWalletPayment == true ? "credit_card" : (automationDraft == nil ? "cash" : ""))
            _selectedCreditCardId = State(initialValue: nil)
        }
    }

    private var expenseCategories: [Category] {
        categories.filter { $0.scope == "expense" || $0.scope == "both" }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        if let workspaceName = automationWorkspaceName {
                            VStack(alignment: .leading, spacing: 6) {
                                Label("Review in \(workspaceName)", systemImage: "tray")
                                    .font(.headline)
                                Text("Confirm the amount and payment method before saving.")
                                    .font(.footnote).foregroundStyle(Theme.muted)
                                if let card = automationDraft?.card, !card.isEmpty {
                                    Text("Wallet card: \(card)")
                                        .font(.footnote).foregroundStyle(Theme.muted)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        HeroAmountField(
                            amountText: $amountText,
                            tint: Theme.expense,
                            focus: $amountFocused,
                            errorMessage: errorMessage
                        )

                        VStack(spacing: 0) {
                            SignalFormRow(label: "Description") {
                                TextField("What was it for?", text: $description)
                                    .focused($descriptionFocused)
                                    .autocorrectionDisabled()
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(Theme.ink)
                                    .multilineTextAlignment(.trailing)
                            }
                            dateRow
                            if !expenseCategories.isEmpty {
                                categoryRow
                            }
                        }

                        paymentSection
                        cardSection
                        if canLinkSplit { splitSection }

                        if let error = errorMessage {
                            Text(error)
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.expense)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        Button(isSaving ? "Saving…" : saveButtonTitle) { save() }
                            .buttonStyle(PrimaryButtonStyle())
                            .disabled(!isValid || isSaving)
                            .padding(.top, 4)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 40)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .disabled(isSaving)
            .interactiveDismissDisabled(isSaving)
            .navigationTitle(isEditing ? "Edit Expense" : "Add Expense")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Theme.muted)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { amountFocused = false; descriptionFocused = false }
                        .foregroundStyle(Theme.accentText)
                        .fontWeight(.semibold)
                }
            }
        }
        .task {
            await loadCreditCards()
            if canLinkSplit { await splitVM.load(workspaceId: workspaceId) }
        }
        .sheet(isPresented: $showNewSplit, onDismiss: {
            if splitWasSaved { completeAutomationSave() }
        }) {
            SplitCreateSheet(
                workspaceId: workspaceId,
                vm: splitVM,
                automationExpense: expenseBody,
                walletPayment: isWalletPayment,
                onSaved: { _ in splitWasSaved = true }
            )
        }
        .onAppear {
            normalizeCardPaymentState()
            if !isEditing && amountText.isEmpty { amountFocused = true }
        }
        .onChange(of: paymentChannel) { _, newValue in
            if newValue == "credit_card" {
                ensureDefaultCreditCard()
            } else {
                selectedCreditCardId = nil
            }
        }
        .onChange(of: canUseCreditCards) { _, _ in normalizeCardPaymentState() }
    }

    // MARK: - Rows

    private var dateRow: some View {
        SignalNativeFormRow {
            DatePicker("Date", selection: $selectedDate, displayedComponents: .date)
                .datePickerStyle(.compact)
                .tint(Theme.accent)
        }
    }

    private var categoryRow: some View {
        SignalNativeFormRow {
            Menu {
                Button("No category") { selectedCategoryId = nil }
                ForEach(expenseCategories) { cat in
                    Button(cat.name) { selectedCategoryId = cat.id }
                }
            } label: {
                HStack(spacing: 8) {
                    Text("Category")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.muted)
                    Spacer(minLength: 16)
                    Text(categoryValueLabel)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(selectedCategoryId == nil ? Theme.faint : Theme.ink)
                        .lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.faint)
                }
            }
        }
    }

    private var saveButtonTitle: String {
        if isEditing { return "Save Changes" }
        if canLinkSplit && splitChoice == "new" { return "Continue to Bill Split" }
        if canLinkSplit && splitChoice == "existing" { return "Link Payment to Split" }
        return "Add Expense"
    }

    private var splitSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionEyebrow("Is this a bill split?")
            SegmentedToggle(selection: $splitChoice, options: [
                ToggleOption(value: "no", label: "No", icon: "person"),
                ToggleOption(value: "existing", label: "Existing", icon: "person.2"),
                ToggleOption(value: "new", label: "New", icon: "plus")
            ])
            if splitChoice == "existing" {
                if splitVM.isLoading {
                    ProgressView("Loading splits…")
                } else if let error = splitVM.errorMessage {
                    Text(error).font(.footnote).foregroundStyle(Theme.expense)
                    Button("Try Again") { Task { await splitVM.load(workspaceId: workspaceId) } }
                } else if splitVM.splits.isEmpty {
                    Text("No bill splits in this workspace. Choose New to create one.")
                        .font(.footnote).foregroundStyle(Theme.muted)
                } else {
                    FormCard {
                        FormMenuRow(label: "Bill split", value: selectedSplit?.merchant ?? "Choose split", isPlaceholder: selectedSplit == nil) {
                            ForEach(splitVM.splits) { split in
                                Button("\(split.merchant) · \(String(split.occurredAt.prefix(10))) · \(formatSplitMoney(split.totalCents, currency: split.currency))") {
                                    selectedSplitId = split.id
                                    Task { await splitVM.loadDetail(workspaceId: workspaceId, splitId: split.id) }
                                }
                            }
                        }
                    }
                    Text("The selected card will be applied to this split's expense.")
                        .font(.footnote).foregroundStyle(Theme.muted)
                    if let selectedSplit, !paymentMatches(selectedSplit) {
                        Text("The payment must match your expense amount in this split. Check the amount or choose another split.")
                            .font(.footnote).foregroundStyle(Theme.warning)
                    }
                }
            }
        }
    }

    private func paymentMatches(_ split: BillSplit) -> Bool {
        guard let body = expenseBody else { return false }
        return AutomationSplitPayment.matches(amountCents: body.amountCents, currency: body.currency, split: split)
    }

    @ViewBuilder
    private var paymentSection: some View {
        if isWalletPayment {
            Label("Apple Pay · Card", systemImage: "creditcard")
                .font(.subheadline).foregroundStyle(Theme.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                SectionEyebrow(paymentChannel.isEmpty ? "Choose Payment Method" : "Payment Method")
                    .padding(.leading, 4)
                SegmentedToggle(
                    selection: $paymentChannel,
                    options: paymentOptions
                )
            }
        }
    }

    @ViewBuilder
    private var cardSection: some View {
        if paymentChannel == "credit_card", canUseCreditCards {
            if let cardLoadError {
                Text(cardLoadError).font(.footnote).foregroundStyle(Theme.warning)
                Button("Reload Cards") { Task { await loadCreditCards() } }
            }
            if creditCards.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 12, weight: .semibold))
                    Text("No cards in this workspace — add one in Cards first.")
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundStyle(Theme.warning)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
            } else {
        SignalNativeFormRow {
            Menu {
                        ForEach(creditCards) { card in
                            Button(cardOptionLabel(card)) { selectedCreditCardId = card.id }
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Text("Card")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(Theme.muted)
                            Spacer(minLength: 16)
                            Text(cardValueLabel)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(selectedCreditCardId == nil ? Theme.faint : Theme.ink)
                                .lineLimit(1)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Theme.faint)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Derived values

    private var isValid: Bool {
        let hasDescription = !description.trimmingCharacters(in: .whitespaces).isEmpty
        let normalized = amountText.replacingOccurrences(of: ",", with: ".")
        let amount = Double(normalized) ?? 0
        let hasAmount = amount.isFinite && amount >= 0.005 && amount < Double(Int.max / 100)
        let cardOK = (!isWalletPayment || canUseCreditCards) && (effectivePaymentChannel != "credit_card" || effectiveCreditCardId != nil)
        let splitOK = !canLinkSplit || splitChoice == "no" || splitChoice == "new"
            || (splitChoice == "existing" && selectedSplit.map(paymentMatches) == true && !splitVM.isLoading)
        return hasDescription && hasAmount && cardOK && splitOK && ["cash", "credit_card"].contains(paymentChannel)
    }

    private var paymentOptions: [ToggleOption] {
        var options = [ToggleOption(value: "cash", label: "Cash", icon: "banknote.fill")]
        if canUseCreditCards {
            options.append(ToggleOption(value: "credit_card", label: "Credit Card", icon: "creditcard.fill"))
        }
        return options
    }

    private var categoryValueLabel: String {
        guard let id = selectedCategoryId,
              let cat = expenseCategories.first(where: { $0.id == id }) else { return "None" }
        return cat.name
    }

    private var cardValueLabel: String {
        guard let id = selectedCreditCardId,
              let card = creditCards.first(where: { $0.id == id }) else {
            return creditCards.isEmpty ? "No cards" : "Select card"
        }
        return cardOptionLabel(card)
    }

    private func cardOptionLabel(_ card: CreditCard) -> String {
        if let lastFour = card.lastFour, !lastFour.isEmpty {
            return "\(card.label) · •••• \(lastFour)"
        }
        return card.label
    }

    /// A stale session can revoke card access while an edit sheet is open. Do
    /// not let that old UI state leak a gated payment channel into a request.
    private func normalizeCardPaymentState() {
        guard !canUseCreditCards else { return }
        paymentChannel = "cash"
        selectedCreditCardId = nil
        creditCards = []
    }

    // MARK: - Data + save

    @MainActor
    private func loadCreditCards() async {
        cardLoadError = nil
        guard canUseCreditCards else { return }
        do {
            let resp: CreditCardsResponse = try await APIClient.shared.fetch(Endpoints.creditCards(workspaceId))
            creditCards = resp.creditCards.filter { !$0.isArchived || $0.id == expense?.creditCardId }
            if isWalletPayment && selectedCreditCardId == nil {
                selectedCreditCardId = WalletCardMatcher.match(automationDraft?.card ?? "", cards: creditCards)
            }
            ensureDefaultCreditCard()
        } catch {
            cardLoadError = "Couldn’t load cards. Try again before saving."
        }
    }

    private func ensureDefaultCreditCard() {
        guard paymentChannel == "credit_card", !creditCards.isEmpty, !isWalletPayment else { return }
        if selectedCreditCardId == nil || !creditCards.contains(where: { $0.id == selectedCreditCardId }) {
            selectedCreditCardId = creditCards[0].id
        }
    }

    private var expenseBody: CreateExpenseBody? {
        guard let amount = Double(amountText.replacingOccurrences(of: ",", with: ".")),
              amount.isFinite, amount >= 0.005, amount < Double(Int.max / 100) else { return nil }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return CreateExpenseBody(description: description, amountCents: Int((amount * 100).rounded()),
            occurredAt: f.string(from: selectedDate), categoryId: selectedCategoryId,
            paymentChannel: effectivePaymentChannel, creditCardId: effectiveCreditCardId)
    }

    private func completeAutomationSave() {
        NotificationCenter.default.post(name: .expenseAutomationSaved, object: nil)
        dismiss()
    }

    private func save() {
        guard !isWalletPayment || canUseCreditCards else {
            errorMessage = "Credit cards are disabled for this account."
            return
        }
        normalizeCardPaymentState()
        guard !description.trimmingCharacters(in: .whitespaces).isEmpty else {
            errorMessage = "Description is required."
            return
        }
        let normalized = amountText.replacingOccurrences(of: ",", with: ".")
        guard let amount = Double(normalized), amount.isFinite, amount > 0, amount < Double(Int.max / 100) else {
            errorMessage = "Enter a valid amount."
            return
        }
        guard ["cash", "credit_card"].contains(paymentChannel) else {
            errorMessage = "Choose a payment method."
            return
        }
        let cents = Int((amount * 100).rounded())
        guard cents > 0 else {
            errorMessage = "Enter an amount of at least 0.01."
            return
        }
        if effectivePaymentChannel == "credit_card" {
            guard effectiveCreditCardId != nil else {
                errorMessage = creditCards.isEmpty ? "Add a credit card first." : "Select a credit card."
                return
            }
        }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        let dateStr = f.string(from: selectedDate)
        let body = CreateExpenseBody(
            description: description,
            amountCents: cents,
            occurredAt: dateStr,
            categoryId: selectedCategoryId,
            paymentChannel: effectivePaymentChannel,
            creditCardId: effectiveCreditCardId
        )
        if canLinkSplit && splitChoice == "new" {
            showNewSplit = true
            return
        }
        if canLinkSplit && splitChoice == "existing" {
            guard let split = selectedSplit, paymentMatches(split), !isSaving else { return }
            isSaving = true
            errorMessage = nil
            Task { @MainActor in
                defer { isSaving = false }
                let saved = await splitVM.updatePaymentMethod(workspaceId: workspaceId, splitId: split.id,
                    body: BillSplitPaymentMethodBody(version: split.version, paymentChannel: body.paymentChannel,
                        creditCardId: body.creditCardId))
                if saved { completeAutomationSave() }
                else { errorMessage = splitVM.errorMessage }
            }
            return
        }
        guard !canLinkSplit || splitChoice == "no" else { return }
        if let saveAction {
            guard !isSaving else { return }
            isSaving = true
            errorMessage = nil
            Task { @MainActor in
                defer { isSaving = false }
                do {
                    try await saveAction(body)
                    NotificationCenter.default.post(name: .expenseAutomationSaved, object: nil)
                    dismiss()
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        } else {
            onSave(body)
            dismiss()
        }
    }

    private static func formatAmount(_ cents: Int) -> String {
        String(format: "%.2f", Double(cents) / 100.0)
    }

    private static func parseFormDate(_ raw: String) -> Date {
        let formats = ["yyyy-MM-dd'T'HH:mm:ss.SSSZ", "yyyy-MM-dd'T'HH:mm:ssZ", "yyyy-MM-dd"]
        for fmt in formats {
            let f = DateFormatter()
            f.dateFormat = fmt
            if let date = f.date(from: raw) { return date }
        }
        return Date()
    }
}

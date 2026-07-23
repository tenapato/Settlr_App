import SwiftUI

struct ExpenseFormSheet: View {
    let workspaceId: String
    let categories: [Category]
    var expense: Expense?
    let onSave: (CreateExpenseBody) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var description: String
    @State private var amountText: String
    @State private var selectedDate: Date
    @State private var selectedCategoryId: String?
    @State private var paymentChannel: String
    @State private var creditCards: [CreditCard] = []
    @State private var selectedCreditCardId: String?
    @State private var errorMessage: String?
    @FocusState private var amountFocused: Bool
    @FocusState private var descriptionFocused: Bool

    private var isEditing: Bool { expense != nil }

    init(
        workspaceId: String,
        categories: [Category],
        expense: Expense? = nil,
        onSave: @escaping (CreateExpenseBody) -> Void
    ) {
        self.workspaceId = workspaceId
        self.categories = categories
        self.expense = expense
        self.onSave = onSave

        if let expense {
            _description = State(initialValue: expense.description)
            _amountText = State(initialValue: Self.formatAmount(expense.amountCents))
            _selectedDate = State(initialValue: Self.parseFormDate(expense.occurredAt))
            _selectedCategoryId = State(initialValue: expense.categoryId)
            _paymentChannel = State(initialValue: expense.paymentChannel)
            _selectedCreditCardId = State(initialValue: expense.creditCardId)
        } else {
            _description = State(initialValue: "")
            _amountText = State(initialValue: "")
            _selectedDate = State(initialValue: Date())
            _selectedCategoryId = State(initialValue: nil)
            _paymentChannel = State(initialValue: "cash")
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
                        HeroAmountField(amountText: $amountText, tint: Theme.expense, focus: $amountFocused)

                        FormCard {
                            FormTextRow(label: "Description", placeholder: "What was it for?", text: $description, focus: $descriptionFocused)
                            FormRowDivider()
                            dateRow
                            if !expenseCategories.isEmpty {
                                FormRowDivider()
                                categoryRow
                            }
                        }

                        paymentSection
                        cardSection

                        if let error = errorMessage {
                            Text(error)
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.expense)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        Button(isEditing ? "Save Changes" : "Add Expense") { save() }
                            .buttonStyle(PrimaryButtonStyle())
                            .disabled(!isValid)
                            .padding(.top, 4)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 40)
                }
                .scrollDismissesKeyboard(.interactively)
            }
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
                        .foregroundStyle(Theme.accent)
                        .fontWeight(.semibold)
                }
            }
        }
        .preferredColorScheme(.dark)
        .task { await loadCreditCards() }
        .onAppear { if !isEditing { amountFocused = true } }
        .onChange(of: paymentChannel) { _, newValue in
            if newValue == "credit_card" {
                ensureDefaultCreditCard()
            } else {
                selectedCreditCardId = nil
            }
        }
    }

    // MARK: - Rows

    private var dateRow: some View {
        HStack(spacing: 12) {
            Text("Date")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.muted)
            Spacer()
            DatePicker("", selection: $selectedDate, displayedComponents: .date)
                .labelsHidden()
                .datePickerStyle(.compact)
                .tint(Theme.accent)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
    }

    private var categoryRow: some View {
        FormMenuRow(label: "Category", value: categoryValueLabel, isPlaceholder: selectedCategoryId == nil) {
            Button("No category") { selectedCategoryId = nil }
            ForEach(expenseCategories) { cat in
                Button(cat.name) { selectedCategoryId = cat.id }
            }
        }
    }

    private var paymentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionEyebrow("Payment Method")
                .padding(.leading, 4)
            SegmentedToggle(
                selection: $paymentChannel,
                options: [
                    ToggleOption(value: "cash", label: "Cash", icon: "banknote.fill"),
                    ToggleOption(value: "credit_card", label: "Credit Card", icon: "creditcard.fill")
                ]
            )
        }
    }

    @ViewBuilder
    private var cardSection: some View {
        if paymentChannel == "credit_card" {
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
                FormCard {
                    FormMenuRow(label: "Card", value: cardValueLabel, isPlaceholder: selectedCreditCardId == nil) {
                        ForEach(creditCards) { card in
                            Button(cardOptionLabel(card)) { selectedCreditCardId = card.id }
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
        let hasAmount = (Double(normalized) ?? 0) > 0
        let cardOK = paymentChannel != "credit_card" || selectedCreditCardId != nil
        return hasDescription && hasAmount && cardOK
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

    // MARK: - Data + save

    @MainActor
    private func loadCreditCards() async {
        do {
            let resp: CreditCardsResponse = try await APIClient.shared.fetch(Endpoints.creditCards(workspaceId))
            creditCards = resp.creditCards
            ensureDefaultCreditCard()
        } catch {
            creditCards = []
        }
    }

    private func ensureDefaultCreditCard() {
        guard paymentChannel == "credit_card", !creditCards.isEmpty else { return }
        if selectedCreditCardId == nil || !creditCards.contains(where: { $0.id == selectedCreditCardId }) {
            selectedCreditCardId = creditCards[0].id
        }
    }

    private func save() {
        guard !description.trimmingCharacters(in: .whitespaces).isEmpty else {
            errorMessage = "Description is required."
            return
        }
        let normalized = amountText.replacingOccurrences(of: ",", with: ".")
        guard let amount = Double(normalized), amount > 0 else {
            errorMessage = "Enter a valid amount."
            return
        }
        let cents = Int((amount * 100).rounded())
        if paymentChannel == "credit_card" {
            guard selectedCreditCardId != nil else {
                errorMessage = creditCards.isEmpty ? "Add a credit card first." : "Select a credit card."
                return
            }
        }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        let dateStr = f.string(from: selectedDate)
        onSave(CreateExpenseBody(
            description: description,
            amountCents: cents,
            occurredAt: dateStr,
            categoryId: selectedCategoryId,
            paymentChannel: paymentChannel,
            creditCardId: paymentChannel == "credit_card" ? selectedCreditCardId : nil
        ))
        dismiss()
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

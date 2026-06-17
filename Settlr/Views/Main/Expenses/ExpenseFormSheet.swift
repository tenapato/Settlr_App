import SwiftUI

struct ExpenseFormSheet: View {
    let workspaceId: String
    let categories: [Category]
    let onSave: (CreateExpenseBody) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var description = ""
    @State private var amountText = ""
    @State private var selectedDate = Date()
    @State private var selectedCategoryId: String? = nil
    @State private var paymentChannel = "cash"
    @State private var creditCards: [CreditCard] = []
    @State private var selectedCreditCardId: String? = nil
    @State private var errorMessage: String?

    private var expenseCategories: [Category] {
        categories.filter { $0.scope == "expense" || $0.scope == "both" }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "#0e0f11").ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        StyledTextField(placeholder: "Description", text: $description)
                        amountField
                        dateField
                        paymentChannelPicker
                        creditCardPicker
                        categoryPicker

                        if let error = errorMessage {
                            Text(error)
                                .font(.system(size: 13))
                                .foregroundStyle(Color(hex: "#ff6b6b"))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        Spacer()
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("Add Expense")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color(hex: "#8e9197"))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .foregroundStyle(Color(hex: "#c8ff5a"))
                        .fontWeight(.semibold)
                }
            }
        }
        .preferredColorScheme(.dark)
        .task { await loadCreditCards() }
        .onChange(of: paymentChannel) { _, newValue in
            if newValue == "credit_card" {
                ensureDefaultCreditCard()
            } else {
                selectedCreditCardId = nil
            }
        }
    }

    private var amountField: some View {
        HStack {
            Text("MXN $")
                .foregroundStyle(Color(hex: "#8e9197"))
                .font(.system(size: 16))
            TextField("0.00", text: $amountText)
                .keyboardType(.decimalPad)
                .foregroundStyle(Color(hex: "#ecedee"))
                .font(.system(size: 16))
        }
        .formFieldStyle(verticalPadding: 14)
    }

    private var dateField: some View {
        DatePicker("Date", selection: $selectedDate, displayedComponents: .date)
            .foregroundStyle(Color(hex: "#ecedee"))
            .tint(Color(hex: "#c8ff5a"))
            .formFieldStyle(verticalPadding: 12)
    }

    private var paymentChannelPicker: some View {
        Picker("Payment", selection: $paymentChannel) {
            Text("Cash").tag("cash")
            Text("Credit Card").tag("credit_card")
        }
        .pickerStyle(.segmented)
        .tint(Color(hex: "#c8ff5a"))
    }

    @ViewBuilder
    private var creditCardPicker: some View {
        if paymentChannel == "credit_card" {
            if creditCards.isEmpty {
                Text("No cards in workspace")
                    .font(.system(size: 13))
                    .foregroundStyle(Color(hex: "#ffb020"))
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Picker("Card", selection: $selectedCreditCardId) {
                    ForEach(creditCards) { card in
                        Text(cardOptionLabel(card)).tag(Optional(card.id))
                    }
                }
                .foregroundStyle(Color(hex: "#ecedee"))
                .formFieldStyle()
            }
        }
    }

    @ViewBuilder
    private var categoryPicker: some View {
        if !expenseCategories.isEmpty {
            Picker("Category", selection: $selectedCategoryId) {
                Text("No category").tag(String?.none)
                ForEach(expenseCategories) { cat in
                    Text(cat.name).tag(Optional(cat.id))
                }
            }
            .foregroundStyle(Color(hex: "#ecedee"))
            .formFieldStyle()
        }
    }

    private func cardOptionLabel(_ card: CreditCard) -> String {
        if let lastFour = card.lastFour, !lastFour.isEmpty {
            return "\(card.label) · •••• \(lastFour)"
        }
        return card.label
    }

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
}

private extension View {
    func formFieldStyle(verticalPadding: CGFloat = 8) -> some View {
        padding(.horizontal, 16)
            .padding(.vertical, verticalPadding)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(hex: "#15171a"))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color(hex: "#2a2d32"), lineWidth: 1)
                    )
            )
    }
}

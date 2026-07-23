import SwiftUI

struct IncomeFormSheet: View {
    let workspaceId: String
    let categories: [Category]
    var income: Income?
    let onSave: (CreateIncomeBody) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var description: String
    @State private var amountText: String
    @State private var selectedDate: Date
    @State private var selectedCategoryId: String?
    @State private var errorMessage: String?
    @FocusState private var amountFocused: Bool
    @FocusState private var descriptionFocused: Bool

    private var isEditing: Bool { income != nil }

    init(
        workspaceId: String,
        categories: [Category],
        income: Income? = nil,
        onSave: @escaping (CreateIncomeBody) -> Void
    ) {
        self.workspaceId = workspaceId
        self.categories = categories
        self.income = income
        self.onSave = onSave

        if let income {
            _description = State(initialValue: income.description)
            _amountText = State(initialValue: Self.formatAmount(income.amountCents))
            _selectedDate = State(initialValue: Self.parseFormDate(income.occurredAt))
            _selectedCategoryId = State(initialValue: income.categoryId)
        } else {
            _description = State(initialValue: "")
            _amountText = State(initialValue: "")
            _selectedDate = State(initialValue: Date())
            _selectedCategoryId = State(initialValue: nil)
        }
    }

    private var incomeCategories: [Category] {
        categories.filter { $0.scope == "income" || $0.scope == "both" }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        HeroAmountField(amountText: $amountText, tint: Theme.income, focus: $amountFocused)

                        FormCard {
                            FormTextRow(label: "Description", placeholder: "Where from?", text: $description, focus: $descriptionFocused)
                            FormRowDivider()
                            dateRow
                            if !incomeCategories.isEmpty {
                                FormRowDivider()
                                categoryRow
                            }
                        }

                        if let error = errorMessage {
                            Text(error)
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.expense)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        Button(isEditing ? "Save Changes" : "Add Income") { save() }
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
            .navigationTitle(isEditing ? "Edit Income" : "Add Income")
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
        .onAppear { if !isEditing { amountFocused = true } }
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
            ForEach(incomeCategories) { cat in
                Button(cat.name) { selectedCategoryId = cat.id }
            }
        }
    }

    // MARK: - Derived values

    private var isValid: Bool {
        let hasDescription = !description.trimmingCharacters(in: .whitespaces).isEmpty
        let normalized = amountText.replacingOccurrences(of: ",", with: ".")
        let hasAmount = (Double(normalized) ?? 0) > 0
        return hasDescription && hasAmount
    }

    private var categoryValueLabel: String {
        guard let id = selectedCategoryId,
              let cat = incomeCategories.first(where: { $0.id == id }) else { return "None" }
        return cat.name
    }

    // MARK: - Save

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
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        onSave(CreateIncomeBody(
            description: description,
            amountCents: cents,
            occurredAt: f.string(from: selectedDate),
            categoryId: selectedCategoryId
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

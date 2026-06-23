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
                Color(hex: "#0e0f11").ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        StyledTextField(placeholder: "Description", text: $description)

                        HStack {
                            Text("MXN $")
                                .foregroundStyle(Color(hex: "#8e9197"))
                                .font(.system(size: 16))
                            TextField("0.00", text: $amountText)
                                .keyboardType(.decimalPad)
                                .foregroundStyle(Color(hex: "#ecedee"))
                                .font(.system(size: 16))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(hex: "#15171a"))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .strokeBorder(Color(hex: "#2a2d32"), lineWidth: 1)
                                )
                        )

                        DatePicker("Date", selection: $selectedDate, displayedComponents: .date)
                            .foregroundStyle(Color(hex: "#ecedee"))
                            .tint(Color(hex: "#c8ff5a"))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color(hex: "#15171a"))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .strokeBorder(Color(hex: "#2a2d32"), lineWidth: 1)
                                    )
                            )

                        if !incomeCategories.isEmpty {
                            Picker("Category", selection: $selectedCategoryId) {
                                Text("No category").tag(String?.none)
                                ForEach(incomeCategories) { cat in
                                    Text(cat.name).tag(Optional(cat.id))
                                }
                            }
                            .foregroundStyle(Color(hex: "#ecedee"))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color(hex: "#15171a"))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .strokeBorder(Color(hex: "#2a2d32"), lineWidth: 1)
                                    )
                            )
                        }

                        if let error = errorMessage {
                            Text(error)
                                .font(.system(size: 13))
                                .foregroundStyle(Color(hex: "#ff6b6b"))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle(isEditing ? "Edit Income" : "Add Income")
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

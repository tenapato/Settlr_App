import SwiftUI

struct IncomeFormSheet: View {
    let workspaceId: String
    let categories: [Category]
    let onSave: (CreateIncomeBody) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var description = ""
    @State private var amountText = ""
    @State private var selectedDate = Date()
    @State private var selectedCategoryId: String? = nil
    @State private var errorMessage: String?

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
            .navigationTitle("Add Income")
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
}

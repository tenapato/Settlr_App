import SwiftUI

// MARK: - Shared row

private struct TransactionDetailRow: View {
    let label: String
    let value: String
    var valueColor: Color = Color(hex: "#ecedee")

    var body: some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color(hex: "#8e9197"))
            Spacer(minLength: 16)
            Text(value)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(valueColor)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

private struct TransactionDetailCard<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            content()
            Spacer().frame(height: 20)
        }
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(hex: "#15171a"))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Color(hex: "#2a2d32"), lineWidth: 1)
                )
        )
    }
}

private struct TransactionDetailDivider: View {
    var body: some View {
        Divider()
            .overlay(Color(hex: "#2a2d32"))
            .padding(.leading, 16)
    }
}

private extension View {
    func transactionDetailSheetStyle() -> some View {
        self
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationBackground(Color(hex: "#0e0f11"))
            .presentationCornerRadius(24)
            .preferredColorScheme(.dark)
    }
}

// MARK: - Expense detail

struct ExpenseDetailSheet: View {
    let workspaceId: String
    let categories: [Category]
    let cards: [CreditCard]
    let onUpdated: (Expense) -> Void

    @State private var expense: Expense
    @Environment(\.dismiss) private var dismiss
    @State private var showEditForm = false

    init(
        workspaceId: String,
        expense: Expense,
        categories: [Category],
        cards: [CreditCard],
        onUpdated: @escaping (Expense) -> Void
    ) {
        self.workspaceId = workspaceId
        self.categories = categories
        self.cards = cards
        self.onUpdated = onUpdated
        _expense = State(initialValue: expense)
    }

    private var card: CreditCard? {
        guard let cardId = expense.creditCardId else { return nil }
        return cards.first { $0.id == cardId }
    }

    private var paymentLabel: String {
        expense.paymentChannel == "credit_card" ? "Credit Card" : "Cash"
    }

    private var cardLabel: String? {
        guard expense.paymentChannel == "credit_card", let card else { return nil }
        if let lastFour = card.lastFour, !lastFour.isEmpty {
            return "\(card.label) · •••• \(lastFour)"
        }
        return card.label
    }

    private var category: Category? {
        categories.first { $0.id == expense.categoryId }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    header(
                        icon: expense.paymentChannel == "credit_card" ? "creditcard.fill" : "banknote.fill",
                        tint: Color(hex: "#ff6b6b"),
                        amountCents: expense.amountCents,
                        amountColor: Color(hex: "#ecedee")
                    )

                    TransactionDetailCard {
                        HStack(alignment: .top, spacing: 8) {
                            Text(expense.description)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(Color(hex: "#ecedee"))
                                .frame(maxWidth: .infinity, alignment: .leading)
                            ExpenseMarkerTags(expense: expense)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        TransactionDetailDivider()
                        TransactionDetailRow(label: "Date", value: expense.displayDate)
                        TransactionDetailDivider()
                        TransactionDetailRow(label: "Payment", value: paymentLabel)
                        if let cardLabel {
                            TransactionDetailDivider()
                            TransactionDetailRow(label: "Card", value: cardLabel)
                        }
                        if let category {
                            TransactionDetailDivider()
                            TransactionDetailRow(
                                label: "Category",
                                value: category.name,
                                valueColor: categoryColor(category.color)
                            )
                        }
                        TransactionDetailDivider()
                        TransactionDetailRow(label: "Currency", value: expense.currency)
                        if let notes = expense.notes, !notes.isEmpty {
                            TransactionDetailDivider()
                            TransactionDetailRow(label: "Notes", value: notes)
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .padding(.bottom, 14)
            }
            .contentMargins(.bottom, 24, for: .scrollContent)
            .background(Color(hex: "#0e0f11"))
            .navigationTitle("Expense")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showEditForm = true } label: {
                        Image(systemName: "pencil")
                            .foregroundStyle(Color(hex: "#c8ff5a"))
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color(hex: "#c8ff5a"))
                        .fontWeight(.semibold)
                }
            }
        }
        .transactionDetailSheetStyle()
        .sheet(isPresented: $showEditForm) {
            ExpenseFormSheet(
                workspaceId: workspaceId,
                categories: categories,
                expense: expense
            ) { body in
                Task {
                    if let updated = await updateExpense(body) {
                        expense = updated
                        onUpdated(updated)
                    }
                }
            }
        }
    }

    @MainActor
    private func updateExpense(_ body: CreateExpenseBody) async -> Expense? {
        do {
            let response: CreateExpenseResponse = try await APIClient.shared.fetch(
                Endpoints.expense(workspaceId, expense.id),
                method: "PATCH",
                body: body
            )
            return response.expense
        } catch {
            return nil
        }
    }
}

// MARK: - Income detail

struct IncomeDetailSheet: View {
    let workspaceId: String
    let categories: [Category]
    let onUpdated: (Income) -> Void

    @State private var income: Income
    @Environment(\.dismiss) private var dismiss
    @State private var showEditForm = false

    init(
        workspaceId: String,
        income: Income,
        categories: [Category],
        onUpdated: @escaping (Income) -> Void
    ) {
        self.workspaceId = workspaceId
        self.categories = categories
        self.onUpdated = onUpdated
        _income = State(initialValue: income)
    }

    private var category: Category? {
        categories.first { $0.id == income.categoryId }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    header(
                        icon: "arrow.up.circle.fill",
                        tint: Color(hex: "#5ddf8a"),
                        amountCents: income.amountCents,
                        amountColor: Color(hex: "#5ddf8a")
                    )

                    TransactionDetailCard {
                        HStack(alignment: .top, spacing: 8) {
                            Text(income.description)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(Color(hex: "#ecedee"))
                                .frame(maxWidth: .infinity, alignment: .leading)
                            IncomeMarkerTags(income: income)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        TransactionDetailDivider()
                        TransactionDetailRow(label: "Date", value: income.displayDate)
                        if let source = income.source, !source.isEmpty {
                            TransactionDetailDivider()
                            TransactionDetailRow(label: "Source", value: source)
                        }
                        if let category {
                            TransactionDetailDivider()
                            TransactionDetailRow(
                                label: "Category",
                                value: category.name,
                                valueColor: categoryColor(category.color)
                            )
                        }
                        TransactionDetailDivider()
                        TransactionDetailRow(label: "Currency", value: income.currency)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .padding(.bottom, 14)
            }
            .contentMargins(.bottom, 24, for: .scrollContent)
            .background(Color(hex: "#0e0f11"))
            .navigationTitle("Income")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showEditForm = true } label: {
                        Image(systemName: "pencil")
                            .foregroundStyle(Color(hex: "#c8ff5a"))
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color(hex: "#c8ff5a"))
                        .fontWeight(.semibold)
                }
            }
        }
        .transactionDetailSheetStyle()
        .sheet(isPresented: $showEditForm) {
            IncomeFormSheet(
                workspaceId: workspaceId,
                categories: categories,
                income: income
            ) { body in
                Task {
                    if let updated = await updateIncome(body) {
                        income = updated
                        onUpdated(updated)
                    }
                }
            }
        }
    }

    @MainActor
    private func updateIncome(_ body: CreateIncomeBody) async -> Income? {
        do {
            let response: CreateIncomeResponse = try await APIClient.shared.fetch(
                Endpoints.incomeItem(workspaceId, income.id),
                method: "PATCH",
                body: body
            )
            return response.income
        } catch {
            return nil
        }
    }
}

// MARK: - Header

private func header(icon: String, tint: Color, amountCents: Int, amountColor: Color) -> some View {
    VStack(spacing: 14) {
        ZStack {
            Circle()
                .fill(tint.opacity(0.12))
                .frame(width: 56, height: 56)
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundStyle(tint)
        }

        AmountLabel(
            cents: amountCents,
            font: .system(size: 32, weight: .bold)
        )
        .foregroundStyle(amountColor)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 8)
}

private func categoryColor(_ hex: String?) -> Color {
    guard let hex, !hex.isEmpty else { return Color(hex: "#8e9197") }
    return Color(hex: hex)
}

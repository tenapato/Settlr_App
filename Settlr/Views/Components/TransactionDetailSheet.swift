import SwiftUI

// MARK: - Shared row

private struct TransactionDetailRow: View {
    let label: String
    let value: String
    var valueColor: Color = Theme.ink

    var body: some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.muted)
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
                .fill(Theme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Theme.line, lineWidth: 1)
                )
        )
    }
}

private struct TransactionDetailDivider: View {
    var body: some View {
        Divider()
            .overlay(Theme.line)
            .padding(.leading, 16)
    }
}

private struct TransactionRecoveryBanner: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(Theme.warning)
            Text(message)
                .font(.caption)
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Retry", action: onRetry)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.accentText)
                .frame(minWidth: 44, minHeight: 44)
        }
        .padding(.horizontal, 12)
        .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .contain)
    }
}

private enum TransactionRetryAction {
    case edit
    case delete
}

private extension View {
    func transactionDetailSheetStyle() -> some View {
        self
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationBackground(Theme.bg)
            .presentationCornerRadius(24)
    }
}

// MARK: - Expense detail

struct ExpenseDetailSheet: View {
    let workspaceId: String
    let categories: [Category]
    let cards: [CreditCard]
    let onUpdated: (Expense) -> Void
    let onDeleted: (() -> Void)?
    let isWorkspaceCurrent: () -> Bool

    @State private var expense: Expense
    @Environment(\.dismiss) private var dismiss
    @State private var showEditForm = false
    @State private var showDeleteConfirmation = false
    @State private var isDeleting = false
    @State private var operationErrorMessage: String?
    @State private var retryAction: TransactionRetryAction?

    init(
        workspaceId: String,
        expense: Expense,
        categories: [Category],
        cards: [CreditCard],
        onUpdated: @escaping (Expense) -> Void,
        onDeleted: (() -> Void)? = nil,
        isWorkspaceCurrent: @escaping () -> Bool = { true }
    ) {
        self.workspaceId = workspaceId
        self.categories = categories
        self.cards = cards
        self.onUpdated = onUpdated
        self.onDeleted = onDeleted
        self.isWorkspaceCurrent = isWorkspaceCurrent
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
                        tint: Theme.expense,
                        amountCents: expense.amountCents,
                        amountColor: Theme.ink
                    )

                    if let operationErrorMessage {
                        TransactionRecoveryBanner(message: operationErrorMessage) {
                            switch retryAction {
                            case .edit: showEditForm = true
                            case .delete: showDeleteConfirmation = true
                            case nil: break
                            }
                        }
                    }

                    TransactionDetailCard {
                        HStack(alignment: .top, spacing: 8) {
                            Text(expense.description)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(Theme.ink)
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

                    // This expense is the whole bill; the split says how much of
                    // it is actually yours.
                    if let splitId = expense.billSplitId {
                        ExpenseSplitSection(workspaceId: workspaceId, splitId: splitId)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .padding(.bottom, 14)
            }
            .contentMargins(.bottom, 24, for: .scrollContent)
            .background(Theme.bg)
            .navigationTitle("Expense")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: 18) {
                        Button { showEditForm = true } label: {
                            Image(systemName: "pencil")
                                .foregroundStyle(Theme.accentText)
                                .frame(width: 44, height: 44)
                        }
                        if onDeleted != nil {
                            Button(role: .destructive) { showDeleteConfirmation = true } label: {
                                Image(systemName: "trash")
                                    .frame(width: 44, height: 44)
                            }
                            .disabled(isDeleting)
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Theme.accentText)
                        .fontWeight(.semibold)
                }
            }
        }
        .transactionDetailSheetStyle()
        .alert("Delete Expense?", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) { Task { await deleteExpense() } }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This expense will be removed from the workspace.")
        }
        .sheet(isPresented: $showEditForm) {
            ExpenseFormSheet(
                workspaceId: workspaceId,
                categories: categories,
                expense: expense
            ) { body in
                Task {
                    if let updated = await updateExpense(body) {
                        operationErrorMessage = nil
                        retryAction = nil
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
            guard isWorkspaceCurrent() else { return nil }
            return response.expense
        } catch {
            operationErrorMessage = "Couldn’t update this expense. Saved data is unchanged. \(error.localizedDescription)"
            retryAction = .edit
            return nil
        }
    }

    @MainActor
    private func deleteExpense() async {
        guard !isDeleting, let onDeleted else { return }
        isDeleting = true
        defer { isDeleting = false }
        do {
            try await APIClient.shared.send(
                Endpoints.expense(workspaceId, expense.id),
                method: "DELETE"
            )
            guard isWorkspaceCurrent() else { return }
            onDeleted()
            dismiss()
        } catch {
            operationErrorMessage = "Couldn’t delete this expense. It is still saved. \(error.localizedDescription)"
            retryAction = .delete
        }
    }
}

// MARK: - Income detail

struct IncomeDetailSheet: View {
    let workspaceId: String
    let categories: [Category]
    let onUpdated: (Income) -> Void
    let onDeleted: (() -> Void)?
    let isWorkspaceCurrent: () -> Bool

    @State private var income: Income
    @Environment(\.dismiss) private var dismiss
    @State private var showEditForm = false
    @State private var showDeleteConfirmation = false
    @State private var isDeleting = false
    @State private var operationErrorMessage: String?
    @State private var retryAction: TransactionRetryAction?

    init(
        workspaceId: String,
        income: Income,
        categories: [Category],
        onUpdated: @escaping (Income) -> Void,
        onDeleted: (() -> Void)? = nil,
        isWorkspaceCurrent: @escaping () -> Bool = { true }
    ) {
        self.workspaceId = workspaceId
        self.categories = categories
        self.onUpdated = onUpdated
        self.onDeleted = onDeleted
        self.isWorkspaceCurrent = isWorkspaceCurrent
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
                        icon: "arrow.down.circle.fill",
                        tint: Theme.income,
                        amountCents: income.amountCents,
                        amountColor: Theme.income
                    )

                    if let operationErrorMessage {
                        TransactionRecoveryBanner(message: operationErrorMessage) {
                            switch retryAction {
                            case .edit: showEditForm = true
                            case .delete: showDeleteConfirmation = true
                            case nil: break
                            }
                        }
                    }

                    TransactionDetailCard {
                        HStack(alignment: .top, spacing: 8) {
                            Text(income.description)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(Theme.ink)
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
            .background(Theme.bg)
            .navigationTitle("Income")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: 18) {
                        Button { showEditForm = true } label: {
                            Image(systemName: "pencil")
                                .foregroundStyle(Theme.accentText)
                                .frame(width: 44, height: 44)
                        }
                        if onDeleted != nil {
                            Button(role: .destructive) { showDeleteConfirmation = true } label: {
                                Image(systemName: "trash")
                                    .frame(width: 44, height: 44)
                            }
                            .disabled(isDeleting)
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Theme.accentText)
                        .fontWeight(.semibold)
                }
            }
        }
        .transactionDetailSheetStyle()
        .alert("Delete Income?", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) { Task { await deleteIncome() } }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This income will be removed from the workspace.")
        }
        .sheet(isPresented: $showEditForm) {
            IncomeFormSheet(
                workspaceId: workspaceId,
                categories: categories,
                income: income
            ) { body, _ in
                Task {
                    if let updated = await updateIncome(body) {
                        operationErrorMessage = nil
                        retryAction = nil
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
            guard isWorkspaceCurrent() else { return nil }
            return response.income
        } catch {
            operationErrorMessage = "Couldn’t update this income. Saved data is unchanged. \(error.localizedDescription)"
            retryAction = .edit
            return nil
        }
    }

    @MainActor
    private func deleteIncome() async {
        guard !isDeleting, let onDeleted else { return }
        isDeleting = true
        defer { isDeleting = false }
        do {
            try await APIClient.shared.send(
                Endpoints.incomeItem(workspaceId, income.id),
                method: "DELETE"
            )
            guard isWorkspaceCurrent() else { return }
            onDeleted()
            dismiss()
        } catch {
            operationErrorMessage = "Couldn’t delete this income. It is still saved. \(error.localizedDescription)"
            retryAction = .delete
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
    guard let hex, !hex.isEmpty else { return Theme.muted }
    return Color(hex: hex)
}

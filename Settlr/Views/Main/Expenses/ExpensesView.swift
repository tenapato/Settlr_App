import SwiftUI

// MARK: - FilterChip (shared with IncomeView)

struct FilterChip<Content: View>: View {
    let label: String
    let value: String
    @ViewBuilder let content: () -> Content

    var isActive: Bool { value != "Any" }

    var body: some View {
        Menu {
            content()
        } label: {
            HStack(spacing: 4) {
                Text(isActive ? "\(label): \(value)" : label)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isActive ? Color(hex: "#0e0f11") : Color(hex: "#8e9197"))
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(isActive ? Color(hex: "#0e0f11").opacity(0.6) : Color(hex: "#5a5d63"))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(isActive ? Color(hex: "#c8ff5a") : Color(hex: "#1c1f23"))
                    .overlay(Capsule().strokeBorder(isActive ? Color.clear : Color(hex: "#2a2d32"), lineWidth: 1))
            )
            .animation(.spring(duration: 0.2), value: isActive)
        }
    }
}

// MARK: - ExpensesView

struct ExpensesView: View {
    let workspaceId: String
    @Binding var showForm: Bool
    @State private var vm = ExpensesVM()
    @State private var selectedExpense: Expense?
    @State private var expenseToDelete: Expense?

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "#0e0f11").ignoresSafeArea()

                VStack(spacing: 0) {
                    ExpenseMonthSelectorBar(selectedMonth: $vm.selectedMonth) {
                        Task { await vm.load(workspaceId: workspaceId) }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 8)

                    SearchBar(text: $vm.searchText, placeholder: "Search expenses…")
                        .padding(.horizontal, 24)
                        .padding(.bottom, 8)

                    filterChipsRow
                        .padding(.bottom, 8)

                    if vm.isLoading {
                        Spacer()
                        ProgressView().tint(Color(hex: "#c8ff5a"))
                        Spacer()
                    } else if vm.filteredExpenses.isEmpty {
                        expenseEmptyState
                    } else {
                        expenseList
                    }
                }
            }
            .navigationTitle("Expenses")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showForm = true } label: {
                        Image(systemName: "plus")
                            .foregroundStyle(Color(hex: "#c8ff5a"))
                            .font(.system(size: 18, weight: .semibold))
                    }
                }
            }
            .sheet(isPresented: $showForm) {
                ExpenseFormSheet(workspaceId: workspaceId, categories: vm.categories) { body in
                    Task { await vm.create(workspaceId: workspaceId, body: body) }
                }
            }
            .sheet(item: $selectedExpense) { expense in
                ExpenseDetailSheet(
                    workspaceId: workspaceId,
                    expense: expense,
                    categories: vm.categories,
                    cards: vm.cards,
                    onUpdated: { updated in
                        if let idx = vm.expenses.firstIndex(where: { $0.id == updated.id }) {
                            vm.expenses[idx] = updated
                        }
                        selectedExpense = updated
                    }
                )
            }
            .overlay {
                if let expense = expenseToDelete {
                    DeleteConfirmDialog(
                        title: "Delete Expense?",
                        itemName: expense.description,
                        onConfirm: {
                            Task { await vm.delete(workspaceId: workspaceId, expenseId: expense.id) }
                            expenseToDelete = nil
                        },
                        onCancel: { expenseToDelete = nil }
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }
            }
            .animation(.easeOut(duration: 0.2), value: expenseToDelete != nil)
        }
        .preferredColorScheme(.dark)
        .task { await vm.load(workspaceId: workspaceId) }
        .onChange(of: vm.selectedMonth) { _, _ in
            Task { await vm.load(workspaceId: workspaceId) }
        }
    }

    // MARK: - Filter chips

    private var filterChipsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterChip(label: "Channel", value: channelValue) {
                    Button("Any") { vm.filterChannel = nil }
                    Button("Cash") { vm.filterChannel = "cash" }
                    Button("Card") { vm.filterChannel = "credit_card" }
                }

                if !vm.cards.isEmpty {
                    FilterChip(label: "Card", value: cardValue) {
                        Button("Any") { vm.filterCardId = nil }
                        ForEach(vm.cards) { card in
                            Button(card.label) { vm.filterCardId = card.id }
                        }
                    }
                }

                FilterChip(label: "Category", value: categoryValue) {
                    Button("Any") { vm.filterCategoryId = nil }
                    ForEach(vm.categories) { cat in
                        Button(cat.name) { vm.filterCategoryId = cat.id }
                    }
                }

                if vm.hasActiveFilter {
                    Button {
                        vm.clearFilters()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(Color(hex: "#5a5d63"))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 24)
        }
    }

    private var channelValue: String {
        switch vm.filterChannel {
        case "cash": return "Cash"
        case "credit_card": return "Card"
        default: return "Any"
        }
    }

    private var cardValue: String {
        guard let id = vm.filterCardId,
              let card = vm.cards.first(where: { $0.id == id }) else { return "Any" }
        return card.label
    }

    private var categoryValue: String {
        guard let id = vm.filterCategoryId,
              let cat = vm.categories.first(where: { $0.id == id }) else { return "Any" }
        return cat.name
    }

    // MARK: - List

    private var expenseList: some View {
        List {
            ForEach(vm.filteredExpenses) { expense in
                Button {
                    selectedExpense = expense
                } label: {
                    ExpenseRow(expense: expense, vm: vm)
                }
                .buttonStyle(.plain)
                .listRowBackground(Color(hex: "#15171a"))
                .listRowSeparatorTint(Color(hex: "#2a2d32"))
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            expenseToDelete = expense
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
            }

            // Footer: count + total
            HStack {
                let count = vm.filteredExpenses.count
                Text("\(count) expense\(count == 1 ? "" : "s")")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color(hex: "#5a5d63"))
                Spacer()
                AmountLabel(
                    cents: vm.filteredExpenses.reduce(0) { $0 + $1.amountCents },
                    font: .system(size: 12, weight: .semibold)
                )
                .foregroundStyle(Color(hex: "#8e9197"))
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 10)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            Spacer().frame(height: 100)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .refreshable { await vm.load(workspaceId: workspaceId) }
    }

    // MARK: - Empty state

    private var expenseEmptyState: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: vm.hasActiveFilter ? "magnifyingglass" : "tray")
                .font(.system(size: 36))
                .foregroundStyle(Color(hex: "#5a5d63"))
            Text(vm.hasActiveFilter ? "No matching expenses" : "No expenses this month")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color(hex: "#8e9197"))
            if vm.hasActiveFilter {
                Text("Try a different search or clear the filters.")
                    .font(.system(size: 13))
                    .foregroundStyle(Color(hex: "#5a5d63"))
                    .multilineTextAlignment(.center)
                Button {
                    vm.clearFilters()
                } label: {
                    Text("Clear filters")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color(hex: "#0e0f11"))
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Color(hex: "#c8ff5a"))
                        .clipShape(Capsule())
                }
            } else {
                Button {
                    showForm = true
                } label: {
                    Text("Add your first expense")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color(hex: "#0e0f11"))
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Color(hex: "#c8ff5a"))
                        .clipShape(Capsule())
                }
            }
            Spacer()
        }
        .padding(.horizontal, 32)
    }
}

// MARK: - SearchBar

struct SearchBar: View {
    @Binding var text: String
    let placeholder: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color(hex: "#5a5d63"))

            TextField(placeholder, text: $text)
                .font(.system(size: 15))
                .foregroundStyle(Color(hex: "#ecedee"))
                .autocorrectionDisabled()
                .autocapitalization(.none)

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Color(hex: "#5a5d63"))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(hex: "#15171a"))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color(hex: "#2a2d32"), lineWidth: 1))
        )
    }
}

// MARK: - ExpenseRow

private struct ExpenseRow: View {
    let expense: Expense
    let vm: ExpensesVM

    private var category: Category? {
        guard let id = expense.categoryId else { return nil }
        return vm.categories.first { $0.id == id }
    }

    private var card: CreditCard? {
        guard let id = expense.creditCardId else { return nil }
        return vm.cards.first { $0.id == id }
    }

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color(hex: "#ff6b6b").opacity(0.12))
                    .frame(width: 40, height: 40)
                Image(systemName: expense.paymentChannel == "credit_card" ? "creditcard.fill" : "banknote.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(Color(hex: "#ff6b6b"))
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(expense.description)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color(hex: "#ecedee"))
                        .lineLimit(1)
                        .truncationMode(.tail)

                    ExpenseMarkerTags(expense: expense)
                }

                HStack(spacing: 6) {
                    Text(expense.displayDate)
                        .font(.system(size: 12))
                        .foregroundStyle(Color(hex: "#5a5d63"))

                    if let channel = expense.channelTagLabel {
                        LedgerTag(text: channel, tone: expense.paymentChannel == "credit_card" ? .accent : .neutral)
                    }

                    if let cat = category {
                        CategoryBadge(name: cat.name, color: cat.color)
                    }

                    if expense.paymentChannel == "credit_card",
                       let lf = card?.lastFour {
                        Text("····\(lf)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Color(hex: "#5a5d63"))
                    }
                }
            }

            Spacer()

            AmountLabel(cents: expense.amountCents, font: .system(size: 15, weight: .semibold))
                .foregroundStyle(Color(hex: "#ecedee"))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Color(hex: "#15171a"))
    }
}

// MARK: - Month selector

private struct ExpenseMonthSelectorBar: View {
    @Binding var selectedMonth: String
    let onChanged: () -> Void

    var body: some View {
        HStack {
            Button { change(by: -1) } label: {
                Image(systemName: "chevron.left")
                    .foregroundStyle(Color(hex: "#8e9197"))
            }
            Spacer()
            Button {
                let f = DateFormatter(); f.dateFormat = "yyyy-MM"
                selectedMonth = f.string(from: Date())
                onChanged()
            } label: {
                Text(displayLabel)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(hex: "#ecedee"))
                    .contentTransition(.numericText())
                    .animation(.snappy(duration: 0.2), value: selectedMonth)
            }
            .buttonStyle(.plain)
            Spacer()
            Button { change(by: 1) } label: {
                Image(systemName: "chevron.right")
                    .foregroundStyle(Color(hex: "#8e9197"))
            }
        }
        .padding(.vertical, 12)
    }

    private var displayLabel: String {
        let parts = selectedMonth.split(separator: "-")
        guard parts.count == 2, let y = Int(parts[0]), let m = Int(parts[1]) else { return selectedMonth }
        var comps = DateComponents(); comps.year = y; comps.month = m; comps.day = 1
        guard let date = Calendar.current.date(from: comps) else { return selectedMonth }
        let f = DateFormatter(); f.dateFormat = "MMMM yyyy"
        return f.string(from: date)
    }

    private func change(by delta: Int) {
        let parts = selectedMonth.split(separator: "-")
        guard parts.count == 2, let y = Int(parts[0]), let m = Int(parts[1]) else { return }
        var comps = DateComponents(); comps.year = y; comps.month = m + delta; comps.day = 1
        guard let date = Calendar.current.date(from: comps) else { return }
        let f = DateFormatter(); f.dateFormat = "yyyy-MM"
        selectedMonth = f.string(from: date)
        onChanged()
    }
}

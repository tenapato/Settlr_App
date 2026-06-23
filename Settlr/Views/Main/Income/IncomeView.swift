import SwiftUI

struct IncomeView: View {
    let workspaceId: String
    @Binding var showForm: Bool
    @State private var vm = IncomeVM()
    @State private var selectedIncome: Income?
    @State private var incomeToDelete: Income?

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "#0e0f11").ignoresSafeArea()

                VStack(spacing: 0) {
                    IncomeMonthSelectorBar(selectedMonth: $vm.selectedMonth) {
                        Task { await vm.load(workspaceId: workspaceId) }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 8)

                    SearchBar(text: $vm.searchText, placeholder: "Search income…")
                        .padding(.horizontal, 24)
                        .padding(.bottom, 8)

                    incomeFilterChipsRow
                        .padding(.bottom, 8)

                    if vm.isLoading {
                        Spacer()
                        ProgressView().tint(Color(hex: "#c8ff5a"))
                        Spacer()
                    } else if vm.filteredIncomes.isEmpty {
                        incomeEmptyState
                    } else {
                        incomeList
                    }
                }
            }
            .navigationTitle("Income")
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
                IncomeFormSheet(workspaceId: workspaceId, categories: vm.categories) { body in
                    Task { await vm.create(workspaceId: workspaceId, body: body) }
                }
            }
            .sheet(item: $selectedIncome) { income in
                IncomeDetailSheet(
                    workspaceId: workspaceId,
                    income: income,
                    categories: vm.categories,
                    onUpdated: { updated in
                        if let idx = vm.incomes.firstIndex(where: { $0.id == updated.id }) {
                            vm.incomes[idx] = updated
                        }
                        selectedIncome = updated
                    }
                )
            }
            .overlay {
                if let income = incomeToDelete {
                    DeleteConfirmDialog(
                        title: "Delete Income?",
                        itemName: income.description,
                        onConfirm: {
                            Task { await vm.delete(workspaceId: workspaceId, incomeId: income.id) }
                            incomeToDelete = nil
                        },
                        onCancel: { incomeToDelete = nil }
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }
            }
            .animation(.easeOut(duration: 0.2), value: incomeToDelete != nil)
        }
        .preferredColorScheme(.dark)
        .task { await vm.load(workspaceId: workspaceId) }
        .onChange(of: vm.selectedMonth) { _, _ in
            Task { await vm.load(workspaceId: workspaceId) }
        }
    }

    // MARK: - Filter chips

    private var incomeFilterChipsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterChip(label: "Category", value: incomeCategoryValue) {
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

    private var incomeCategoryValue: String {
        guard let id = vm.filterCategoryId,
              let cat = vm.categories.first(where: { $0.id == id }) else { return "Any" }
        return cat.name
    }

    // MARK: - List

    private var incomeList: some View {
        List {
            ForEach(vm.filteredIncomes) { item in
                Button {
                    selectedIncome = item
                } label: {
                    IncomeRow(item: item, categories: vm.categories)
                }
                .buttonStyle(.plain)
                .listRowBackground(Color(hex: "#15171a"))
                .listRowSeparatorTint(Color(hex: "#2a2d32"))
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            incomeToDelete = item
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
            }

            // Footer: count + total
            HStack {
                let count = vm.filteredIncomes.count
                Text("\(count) income entr\(count == 1 ? "y" : "ies")")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color(hex: "#5a5d63"))
                Spacer()
                AmountLabel(
                    cents: vm.filteredIncomes.reduce(0) { $0 + $1.amountCents },
                    font: .system(size: 12, weight: .semibold)
                )
                .foregroundStyle(Color(hex: "#5ddf8a"))
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

    private var incomeEmptyState: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: vm.hasActiveFilter ? "magnifyingglass" : "tray")
                .font(.system(size: 36))
                .foregroundStyle(Color(hex: "#5a5d63"))
            Text(vm.hasActiveFilter ? "No matching income" : "No income this month")
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
                    Text("Add income")
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

// MARK: - IncomeRow

private struct IncomeRow: View {
    let item: Income
    let categories: [Category]

    private var category: Category? {
        guard let id = item.categoryId else { return nil }
        return categories.first { $0.id == id }
    }

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color(hex: "#5ddf8a").opacity(0.12))
                    .frame(width: 40, height: 40)
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(Color(hex: "#5ddf8a"))
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(item.description)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color(hex: "#ecedee"))
                        .lineLimit(1)
                        .truncationMode(.tail)

                    IncomeMarkerTags(income: item)
                }

                HStack(spacing: 6) {
                    Text(item.displayDate)
                        .font(.system(size: 12))
                        .foregroundStyle(Color(hex: "#5a5d63"))

                    if let source = item.source, !source.isEmpty {
                        Text(source)
                            .font(.system(size: 11))
                            .foregroundStyle(Color(hex: "#5a5d63"))
                            .lineLimit(1)
                    }

                    if let cat = category {
                        CategoryBadge(name: cat.name, color: cat.color)
                    }
                }
            }

            Spacer()

            AmountLabel(cents: item.amountCents, font: .system(size: 15, weight: .semibold))
                .foregroundStyle(Color(hex: "#5ddf8a"))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Color(hex: "#15171a"))
    }
}

// MARK: - Month selector

private struct IncomeMonthSelectorBar: View {
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

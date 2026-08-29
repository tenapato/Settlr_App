import SwiftUI

// Compatibility state for the global quick-action shell. The Activity screen
// itself is now unified, but the shell still uses this value to choose which
// legacy form to present.
enum ActivitySegment: String, CaseIterable {
    case expenses
    case income
    case savings
}

/// A compact event row aligned to the Signal timeline spine. It deliberately
/// has no surrounding card or detached amount column.
struct SignalTimelineRow: View {
    let event: ActivityEvent
    let isNewest: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(isNewest ? Theme.accent : Theme.muted.opacity(0.7)).frame(width: 8, height: 8)
                if isNewest {
                    Circle().stroke(Theme.accent.opacity(0.35), lineWidth: 5).frame(width: 17, height: 17)
                }
            }
            .frame(width: 18)
            .padding(.top, 6)
            VStack(alignment: .leading, spacing: 4) {
                Text(event.title).font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.ink).lineLimit(1)
                HStack(spacing: 7) {
                    Text(event.context)
                    Text("·")
                    Text(event.occurredAt, format: .dateTime.hour().minute())
                    if let marker = event.marker { Text("·"); Text(marker).foregroundStyle(Theme.accentText) }
                    Spacer(minLength: 4)
                    Text(formatSplitMoney(event.amountCents))
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .foregroundStyle(event.amountCents >= 0 ? Theme.income : Theme.ink)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                .font(.system(size: 12)).foregroundStyle(Theme.muted)
            }
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(event.title), \(event.context)")
        .accessibilityValue("\(formatSplitMoney(event.amountCents)) at \(event.occurredAt, format: .dateTime.hour().minute())")
    }
}

struct ActivityView: View {
    let workspaceId: String
    // Kept in the initializer for source compatibility with the global quick
    // action shell; Activity now uses one unified ledger instead of segments.
    @Binding var selectedSegment: ActivitySegment
    @Binding var showExpenseForm: Bool
    @Binding var showIncomeForm: Bool
    @Binding var showSavingsForm: Bool
    let expensesVM: ExpensesVM
    let incomeVM: IncomeVM
    let savingsVM: SavingsVM

    @Environment(AppState.self) private var appState
    @State private var vm = ActivityVM()
    @State private var showFilterSheet = false
    @State private var selectedExpense: Expense?
    @State private var selectedIncome: Income?
    @State private var selectedSavingsAccount: ActivitySavingsDestination?
    @State private var selectedSplit: ActivitySplitDestination?
    @State private var showSavingsAccounts = false

    private var user: MeUser? { appState.currentUser }
    private var availableTypeFilters: [ActivityFilter] { vm.availableFilters(for: user) }
    private var filteredEvents: [ActivityEvent] { vm.filteredTimeline }
    private var groupedEvents: [(day: Date, events: [ActivityEvent])] {
        let groups = Dictionary(grouping: filteredEvents) { Calendar.current.startOfDay(for: $0.occurredAt) }
        return groups.keys.sorted(by: >).map { ($0, groups[$0] ?? []) }
    }

    private var activitySavingsFormPresentation: Binding<Bool> {
        Binding(
            get: {
                showSavingsForm
                    && user?.has(.savings) == true
                    && savingsVM.loadedWorkspaceID == workspaceId
                    && savingsVM.hasLoadedAccounts
                    && !savingsVM.accounts.isEmpty
                    && savingsVM.errorMessage == nil
            },
            set: { showSavingsForm = $0 }
        )
    }

    var body: some View {
        activityLifecycle
    }

    private var activityBaseNavigation: some View {
        NavigationStack {
            ZStack { Theme.bg.ignoresSafeArea(); content }
                .navigationTitle("Activity")
                .navigationBarTitleDisplayMode(.large)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button { showFilterSheet = true } label: {
                            Label("Filters", systemImage: vm.hasActiveFilter ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle").labelStyle(.iconOnly)
                        }
                        .foregroundStyle(vm.hasActiveFilter ? Theme.accentText : Theme.ink)
                        .frame(minWidth: 44, minHeight: 44)
                        .accessibilityLabel("Filters")
                        .accessibilityValue(vm.activeFilterCount == 0 ? "None" : "\(vm.activeFilterCount) active")
                    }
                ToolbarItem(placement: .navigationBarTrailing) {
                        if user?.has(.expenses) == true {
                            Button { showExpenseForm = true } label: { Image(systemName: "plus").foregroundStyle(Theme.accentText) }
                                .frame(minWidth: 44, minHeight: 44).accessibilityLabel("Add expense")
                        } else if user?.has(.income) == true {
                            Button { showIncomeForm = true } label: { Image(systemName: "plus").foregroundStyle(Theme.accentText) }
                                .frame(minWidth: 44, minHeight: 44).accessibilityLabel("Add income")
                        }
                    }
                }
        }
    }

    private var activityDetailSheets: some View {
        activityBaseNavigation
            .sheet(isPresented: $showFilterSheet) { ActivityFilterSheet(vm: vm, user: user) }
            .sheet(item: $selectedExpense) { expense in
                ExpenseDetailSheet(
                    workspaceId: workspaceId,
                    expense: expense,
                    categories: vm.categories,
                    cards: vm.cards,
                    onUpdated: { updated in
                        guard appState.activeWorkspace?.id == workspaceId else { return }
                        if let index = vm.expenses.firstIndex(where: { $0.id == updated.id }) { vm.expenses[index] = updated }
                        recompute()
                    },
                    onDeleted: {
                        guard appState.activeWorkspace?.id == workspaceId else { return }
                        vm.expenses.removeAll { $0.id == expense.id }
                        selectedExpense = nil
                        recompute()
                    },
                    isWorkspaceCurrent: { appState.activeWorkspace?.id == workspaceId }
                )
            }
            .sheet(item: $selectedIncome) { income in
                IncomeDetailSheet(
                    workspaceId: workspaceId,
                    income: income,
                    categories: vm.categories,
                    onUpdated: { updated in
                        guard appState.activeWorkspace?.id == workspaceId else { return }
                        if let index = vm.incomes.firstIndex(where: { $0.id == updated.id }) { vm.incomes[index] = updated }
                        recompute()
                    },
                    onDeleted: {
                        guard appState.activeWorkspace?.id == workspaceId else { return }
                        vm.incomes.removeAll { $0.id == income.id }
                        selectedIncome = nil
                        recompute()
                    },
                    isWorkspaceCurrent: { appState.activeWorkspace?.id == workspaceId }
                )
            }
            .sheet(item: $selectedSavingsAccount) { destination in
                savingsDestinationView(destination)
            }
            .sheet(item: $selectedSplit) { destination in
                NavigationStack { SplitDetailView(workspaceId: workspaceId, splitId: destination.id, vm: BillSplitVM()) }
            }
    }

    private var activityFormSheets: some View {
        activityDetailSheets
            // Activity owns leaf-form presentation while it is visible;
            // MainTabView's root bindings are inactive on this tab.
            .sheet(isPresented: $showExpenseForm) {
                ExpenseFormSheet(
                    workspaceId: workspaceId,
                    categories: vm.categories.isEmpty ? expensesVM.categories : vm.categories
                ) { body in
                    Task {
                        let generation = await expensesVM.workspaceMutationGeneration(for: workspaceId)
                        await expensesVM.create(
                            workspaceId: workspaceId,
                            body: body,
                            expectedGeneration: generation
                        )
                        await reloadActivityIfCurrentWorkspace()
                    }
                }
            }
            .sheet(isPresented: $showIncomeForm) {
                IncomeFormSheet(
                    workspaceId: workspaceId,
                    categories: vm.categories.isEmpty ? incomeVM.categories : vm.categories
                ) { body, repeatEvery in
                    Task {
                        let generation = await incomeVM.workspaceMutationGeneration(for: workspaceId)
                        if let repeatEvery {
                            _ = await incomeVM.createRecurring(
                                workspaceId: workspaceId,
                                body: CreateRecurringIncomeBody(
                                    amountCents: body.amountCents,
                                    description: body.description,
                                    frequency: repeatEvery.rawValue,
                                    startDate: body.occurredAt,
                                    categoryId: body.categoryId,
                                    reload: false,
                                    expectedGeneration: generation
                                )
                            )
                        } else {
                            await incomeVM.create(
                                workspaceId: workspaceId,
                                body: body,
                                expectedGeneration: generation
                            )
                        }
                        await reloadActivityIfCurrentWorkspace()
                    }
                }
            }
            .sheet(isPresented: activitySavingsFormPresentation) {
                SavingsEntryFormSheet(
                    workspaceId: workspaceId,
                    accounts: savingsVM.accounts,
                    defaultAccountId: savingsVM.selectedAccountId,
                    onSave: { body in
                        Task {
                            let generation = await savingsVM.workspaceMutationGeneration(for: workspaceId)
                            await savingsVM.createEntry(
                                workspaceId: workspaceId,
                                body: body,
                                reload: false,
                                expectedGeneration: generation
                            )
                            await reloadActivityIfCurrentWorkspace()
                        }
                    }
                )
            }
            .sheet(isPresented: $showSavingsAccounts) {
                SavingsAccountsSheet(workspaceId: workspaceId, vm: savingsVM)
            }
    }

    private var activityLifecycle: some View {
        activityFormSheets
        .task(id: workspaceId) {
            showExpenseForm = false
            showIncomeForm = false
            showSavingsForm = false
            showSavingsAccounts = false
            vm.resetForWorkspace()
            // These VMs are shared with the root quick-action presenters. Clear
            // their workspace-owned picker data before a new workspace load.
            expensesVM.resetCategoriesForWorkspace(workspaceId)
            incomeVM.resetCategoriesForWorkspace(workspaceId)
            savingsVM.resetForWorkspace()
            await vm.load(workspaceId: workspaceId, user: user, refreshSession: { await appState.refreshSession() })
            if user?.has(.savings) == true { await savingsVM.load(workspaceId: workspaceId) }
        }
        .onChange(of: showExpenseForm) { _, open in
            guard open else { return }
            Task { await expensesVM.loadCategories(workspaceId: workspaceId) }
        }
        .onChange(of: showIncomeForm) { _, open in
            guard open else { return }
            Task { await incomeVM.loadCategories(workspaceId: workspaceId) }
        }
        .onChange(of: showSavingsForm) { _, open in
            guard open else { return }
            guard appState.currentUser?.has(.savings) == true else { showSavingsForm = false; return }
            Task {
                await savingsVM.load(workspaceId: workspaceId)
                guard appState.activeWorkspace?.id == workspaceId else {
                    showSavingsForm = false
                    return
                }
                guard appState.currentUser?.has(.savings) == true else { showSavingsForm = false; return }
                guard savingsVM.loadedWorkspaceID == workspaceId else {
                    showSavingsForm = false
                    return
                }
                if savingsVM.hasLoadedAccounts, !savingsVM.accounts.isEmpty, savingsVM.errorMessage == nil {
                    return
                } else {
                    showSavingsForm = false
                    showSavingsAccounts = true
                }
            }
        }
        .onChange(of: user?.disabledFeatures) { _, _ in
            let refreshedUser = appState.currentUser
            vm.reconcileFeatures(for: refreshedUser)
            if refreshedUser?.has(.expenses) != true { showExpenseForm = false }
            if refreshedUser?.has(.income) != true { showIncomeForm = false }
            if refreshedUser?.has(.savings) != true {
                showSavingsForm = false
                showSavingsAccounts = false
            }
            Task { await vm.load(workspaceId: workspaceId, user: appState.currentUser, refreshSession: { await appState.refreshSession() }) }
        }
    }

    private func savingsDestinationView(_ destination: ActivitySavingsDestination) -> some View {
        let account: SavingsAccount? = vm.savingsAccounts.first { $0.id == destination.id }
        return SavingsActivityDestinationView(account: account, accountID: destination.id, entries: vm.savings)
    }

    @ViewBuilder private var content: some View {
        VStack(spacing: 0) {
            filterChips.padding(.bottom, 8)
            if vm.isLoading && !vm.hasLoaded && vm.timeline.isEmpty {
                ActivityShapeLoadingView()
            } else if let error = vm.errorMessage, vm.timeline.isEmpty && vm.attentionEvents.isEmpty {
                errorState(error)
            } else if filteredEvents.isEmpty && vm.attentionEvents.isEmpty {
                emptyState
            } else {
                timelineContent
            }
        }
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(availableTypeFilters) { filter in chip(filter.title, selected: vm.selectedFilter == filter) { vm.selectedFilter = filter } }
                ForEach(ActivityPeriodFilter.allCases) { period in chip(period.title, selected: vm.selectedPeriod == period) { vm.selectedPeriod = period } }
                if vm.hasActiveFilter {
                    Button("Reset") { vm.clearFilters() }.font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.accentText).frame(minHeight: 44)
                }
            }.padding(.horizontal, 24)
        }
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(selected ? Theme.accentText : Theme.ink)
                .padding(.horizontal, 12).frame(minHeight: 36)
                .background(selected ? Theme.accent.opacity(0.2) : Theme.surface2).clipShape(Capsule())
                .overlay(Capsule().strokeBorder(selected ? Theme.accent.opacity(0.55) : Theme.line, lineWidth: 1))
        }.buttonStyle(.plain).frame(minHeight: 44)
    }

    private var timelineContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if vm.isLoading, !vm.timeline.isEmpty { SignalTraceLoadingView(lastUpdated: nil).padding(.horizontal, 24) }
                if !vm.attentionEvents.isEmpty { attentionSection }
                ForEach(groupedEvents, id: \.day) { group in
                    Text(group.day, format: .dateTime.weekday(.wide).month(.abbreviated).day())
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.muted).padding(.top, 14).padding(.bottom, 3)
                    HStack(alignment: .top, spacing: 0) {
                        Rectangle().fill(Theme.line).frame(width: 1).padding(.leading, 9)
                        LazyVStack(spacing: 0) {
                            ForEach(group.events) { event in
                                Button { open(event) } label: { SignalTimelineRow(event: event, isNewest: event.id == filteredEvents.first?.id) }
                                    .buttonStyle(.plain)
                            }
                        }.padding(.leading, 5)
                    }
                }
            }.padding(.horizontal, 24).padding(.bottom, 110)
        }
        .refreshable { await vm.load(workspaceId: workspaceId, user: user, refreshSession: { await appState.refreshSession() }) }
    }

    private var attentionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Needs attention").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.warning)
            ForEach(vm.attentionEvents) { split in
                Button { selectedSplit = ActivitySplitDestination(id: split.id) } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "person.2.fill").foregroundStyle(Theme.warning)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(split.merchant).foregroundStyle(Theme.ink)
                            Text("Open split · \(split.pendingCount) waiting").font(.system(size: 12)).foregroundStyle(Theme.muted)
                        }
                        Spacer()
                        Text(formatSplitMoney(split.totalCents, currency: split.currency)).font(.system(size: 13, weight: .medium, design: .monospaced)).foregroundStyle(Theme.ink)
                    }
                }.buttonStyle(.plain).frame(minHeight: 44)
            }
        }.padding(.vertical, 12)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer(); Image(systemName: "waveform.path.ecg").font(.system(size: 24)).foregroundStyle(Theme.muted)
            Text(vm.hasActiveFilter ? "No matching activity" : "No activity yet").font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.ink)
            Text(vm.hasActiveFilter ? "Try resetting the filters." : "Your expenses, income, savings, and splits will appear here.").font(.system(size: 13)).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
            if vm.hasActiveFilter { Button("Reset filters") { vm.clearFilters() }.foregroundStyle(Theme.accentText).frame(minHeight: 44) }; Spacer()
        }.padding(.horizontal, 32)
    }

    private func errorState(_ error: String) -> some View {
        VStack(spacing: 10) {
            Spacer(); Image(systemName: "exclamationmark.triangle").foregroundStyle(Theme.warning)
            Text("Couldn’t load Activity").font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.ink)
            Text(error).font(.system(size: 13)).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
            Button("Try again") { Task { await vm.load(workspaceId: workspaceId, user: user, refreshSession: { await appState.refreshSession() }) } }.foregroundStyle(Theme.accentText).frame(minHeight: 44); Spacer()
        }.padding(.horizontal, 32)
    }

    private func open(_ event: ActivityEvent) {
        switch event.kind {
        case .expense: selectedExpense = vm.expenses.first { $0.id == event.destinationID }
        case .income: selectedIncome = vm.incomes.first { $0.id == event.destinationID }
        case .savings: selectedSavingsAccount = ActivitySavingsDestination(id: event.destinationID)
        case .split: selectedSplit = ActivitySplitDestination(id: event.destinationID)
        }
    }

    private func recompute() {
        let composed = ActivityComposer.compose(expenses: vm.expenses, income: vm.incomes, savings: vm.savings, splits: vm.splits)
        vm.timeline = composed.timeline; vm.attentionEvents = composed.attention
    }

    private func reloadActivityIfCurrentWorkspace() async {
        guard appState.activeWorkspace?.id == workspaceId else { return }
        await vm.load(workspaceId: workspaceId, user: appState.currentUser, refreshSession: { await appState.refreshSession() })
    }
}

private struct ActivityFilterSheet: View {
    let vm: ActivityVM
    let user: MeUser?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var vm = vm
        NavigationStack {
            List {
                if user?.has(.categories) == true && !vm.categories.isEmpty {
                    Section("Categories") {
                        Button("All categories") { vm.selectedCategoryID = nil }
                        ForEach(vm.categories) { category in
                            Button(category.name) { vm.selectedCategoryID = category.id }.foregroundStyle(vm.selectedCategoryID == category.id ? Theme.accentText : Theme.ink)
                        }
                    }
                }
                if user?.has(.creditCards) == true && user?.has(.expenses) == true {
                    Section("Payment source") {
                        Button("Any source") { vm.selectedPaymentSource = nil }
                        Button("Cash") { vm.selectedPaymentSource = "cash" }
                        if !vm.cards.isEmpty { ForEach(vm.cards) { card in Button(card.label) { vm.selectedPaymentSource = card.id } } }
                        else { Button("Card") { vm.selectedPaymentSource = "credit_card" } }
                    }
                }
            }.scrollContentBackground(.hidden).background(Theme.bg).navigationTitle("Filter Activity")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.foregroundStyle(Theme.accentText) }
                    ToolbarItem(placement: .cancellationAction) { Button("Reset") { vm.clearFilters() }.foregroundStyle(Theme.muted) }
                }
        }.presentationDetents([.medium, .large])
    }
}

private struct ActivitySavingsDestination: Identifiable { let id: String }
private struct ActivitySplitDestination: Identifiable { let id: String }

private struct SavingsActivityDestinationView: View {
    let account: SavingsAccount?
    let accountID: String
    let entries: [SavingsEntry]
    private var accountEntries: [SavingsEntry] { entries.filter { $0.accountId == accountID } }

    var body: some View {
        NavigationStack {
            List {
                Section("Account") {
                    Text(account?.name ?? "Savings account")
                    if account == nil { Text(accountID).font(.caption).foregroundStyle(Theme.muted) }
                    if let account { Text(formatSplitMoney(account.balanceCents, currency: account.currency)).font(.system(.title3, design: .monospaced)).foregroundStyle(Theme.ink) }
                }
                Section("Recent movement") {
                    ForEach(accountEntries) { entry in
                        HStack { Text(entry.description); Spacer(); Text(formatSplitMoney(entry.isDeposit ? -entry.amountCents : entry.amountCents)).font(.system(.body, design: .monospaced)) }
                    }
                }
            }.scrollContentBackground(.hidden).background(Theme.bg).navigationTitle(account?.name ?? "Savings")
        }
    }
}

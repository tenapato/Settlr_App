import SwiftUI

struct MainTabView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedTab: Tab = .home
    @State private var activitySegment: ActivitySegment = .expenses
    // Held here, not in the leaf views, so the selected month survives navigation.
    @State private var expensesVM = ExpensesVM()
    @State private var incomeVM = IncomeVM()
    @State private var savingsVM = SavingsVM()
    @State private var fabOpen = false
    @State private var showExpenseForm = false
    @State private var showIncomeForm = false
    @State private var showSavingsForm = false
    @State private var showRootSavingsAccounts = false
    @State private var showCategories = false
    @State private var showSplitList = false
    @State private var showSplitScan = false
    @State private var createdSplitId: String?

    var body: some View {
        ZStack(alignment: .bottom) {
            tabContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            bottomBar
                .padding(.horizontal, 16)
                .padding(.bottom, 16)

            if !quickActionItems.isEmpty {
                QuickActionLauncher(
                    items: quickActionItems,
                    isOpen: fabOpen,
                    onSetOpen: setFabOpen
                )
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(.trailing, 16)
                    .padding(.bottom, 16)
            }
        }
        .background(Theme.bg)
        // A tab can disappear under the user: an admin turns a feature off and
        // the next `/api/me` drops it. Landing on Home beats rendering a tab
        // whose content no longer exists.
        .onAppear(perform: reconcileSelectedTab)
        .onChange(of: availableTabs) { _, _ in reconcileSelectedTab() }
        // Splitting starts at the camera, not at a form.
        .fullScreenCover(isPresented: $showSplitScan) {
            SplitScanFlow(workspaceId: appState.activeWorkspace?.id ?? "") { outcome in
                // Only a split that reached the server has an id worth opening.
                // A queued one lands in the list's "Waiting to upload" section,
                // and deep-linking a local id would spin forever.
                if case .created(let split) = outcome { createdSplitId = split.id }
                showSplitList = true
            }
        }
        .sheet(isPresented: $showSplitList) {
            SplitListView(
                workspaceId: appState.activeWorkspace?.id ?? "",
                initialSplitId: createdSplitId
            )
            .onDisappear { createdSplitId = nil }
        }
        // Activity's leaf views own these sheets while Activity is visible. The
        // root presenters cover global quick actions opened from another tab.
        .sheet(isPresented: rootExpenseFormPresentation) {
            ExpenseFormSheet(workspaceId: appState.activeWorkspace?.id ?? "", categories: expensesVM.categories) { body in
                Task { await expensesVM.create(workspaceId: appState.activeWorkspace?.id ?? "", body: body) }
            }
        }
        .sheet(isPresented: rootIncomeFormPresentation) {
            IncomeFormSheet(workspaceId: appState.activeWorkspace?.id ?? "", categories: incomeVM.categories) { body, repeatEvery in
                Task {
                    if let repeatEvery {
                        _ = await incomeVM.createRecurring(
                            workspaceId: appState.activeWorkspace?.id ?? "",
                            body: CreateRecurringIncomeBody(
                                amountCents: body.amountCents,
                                description: body.description,
                                frequency: repeatEvery.rawValue,
                                startDate: body.occurredAt,
                                categoryId: body.categoryId
                            )
                        )
                    } else {
                        await incomeVM.create(workspaceId: appState.activeWorkspace?.id ?? "", body: body)
                    }
                }
            }
        }
        .sheet(isPresented: rootSavingsFormPresentation) {
            SavingsEntryFormSheet(
                workspaceId: rootWorkspaceID,
                accounts: savingsVM.accounts,
                defaultAccountId: savingsVM.selectedAccountId,
                onSave: { body in
                    Task {
                        let generation = savingsVM.workspaceMutationGeneration(for: rootWorkspaceID)
                        await savingsVM.createEntry(
                            workspaceId: rootWorkspaceID,
                            body: body,
                            expectedGeneration: generation
                        )
                    }
                }
            )
        }
        .sheet(isPresented: rootSavingsAccountsPresentation) {
            SavingsAccountsSheet(workspaceId: rootWorkspaceID, vm: savingsVM)
        }
        .sheet(isPresented: $showCategories) {
            CategoriesView(workspaceId: appState.activeWorkspace?.id ?? "")
        }
    }

    private func setFabOpen(_ open: Bool) {
        fabOpen = open
    }

    private var rootExpenseFormPresentation: Binding<Bool> {
        Binding(get: { showExpenseForm && selectedTab != .activity }, set: { showExpenseForm = $0 })
    }

    private var rootIncomeFormPresentation: Binding<Bool> {
        Binding(get: { showIncomeForm && selectedTab != .activity }, set: { showIncomeForm = $0 })
    }

    private var rootSavingsFormPresentation: Binding<Bool> {
        Binding(
            get: {
                showSavingsForm
                    && selectedTab != .savings
                    && selectedTab != .activity
                    && savingsVM.loadedWorkspaceID == rootWorkspaceID
                    && savingsVM.accountsRequestIsSettled(for: rootWorkspaceID)
                    && savingsVM.hasLoadedAccounts
                    && !savingsVM.accounts.isEmpty
                    && savingsVM.accountsErrorMessage == nil
            },
            set: { showSavingsForm = $0 }
        )
    }

    private var rootWorkspaceID: String { appState.activeWorkspace?.id ?? "" }

    private var rootSavingsAccountsPresentation: Binding<Bool> {
        Binding(
            get: {
                showRootSavingsAccounts && selectedTab != .savings && selectedTab != .activity
            },
            set: { showRootSavingsAccounts = $0 }
        )
    }

    private func prepareGlobalSavingsForm() {
        guard appState.currentUser?.has(.savings) == true, !rootWorkspaceID.isEmpty else { return }
        // Activity owns the account-aware presenter. Reuse its binding so the
        // global launcher cannot race it with a second root sheet.
        if selectedTab == .activity {
            showSavingsForm = true
            return
        }
        guard selectedTab != .savings else { return }
        let workspaceId = rootWorkspaceID
        Task { @MainActor in
            await savingsVM.load(workspaceId: workspaceId)
            guard appState.activeWorkspace?.id == workspaceId,
                  selectedTab != .savings,
                  selectedTab != .activity,
                  appState.currentUser?.has(.savings) == true else { return }
            showSavingsForm = false
            if savingsVM.accountsRequestIsSettled(for: workspaceId),
               savingsVM.hasLoadedAccounts,
               !savingsVM.accounts.isEmpty,
               savingsVM.accountsErrorMessage == nil {
                showSavingsForm = true
            } else {
                showRootSavingsAccounts = true
            }
        }
    }

    // MARK: - Feature availability

    private var availableTabs: [Tab] { Tab.available(for: appState.currentUser) }

    private func reconcileSelectedTab() {
        if appState.currentUser?.has(.savings) != true {
            showSavingsForm = false
            showRootSavingsAccounts = false
        }
        guard !availableTabs.contains(selectedTab) else { return }
        selectedTab = .home
        // An open palette may have been showing actions that just went away.
        if fabOpen { setFabOpen(false) }
    }

    // MARK: - Action items

    private var quickActionItems: [QuickActionItem] {
        var actions: [QuickActionItem] = []
        // Bill splitting lives only here — it is a one-off action, not a place
        // you navigate to, so it stays out of the tab bar.
        if appState.currentUser?.has(.billSplits) ?? false {
            // The pending count rides on the label because the split list lives
            // behind a sheet — without it, a split waiting to upload is
            // invisible until the user happens to go looking for it.
            let waiting = appState.currentUser.map { PendingSplitQueue.shared.pendingCount(userId: $0.id) } ?? 0
            actions.append(
                QuickActionItem(
                    id: "scan-and-split",
                    title: "Scan and split",
                    subtitle: waiting > 0
                        ? "\(waiting) split\(waiting == 1 ? "" : "s") waiting to upload"
                        : "Scan a receipt",
                    systemImage: "doc.viewfinder", role: .signature
                ) {
                    setFabOpen(false)
                    Task {
                        try? await Task.sleep(nanoseconds: 320_000_000)
                        showSplitScan = true
                    }
                }
            )
        }
        actions.append(contentsOf: ledgerActions)
        return actions
    }

    /// One entry per Activity segment, so a segment the admin turned off can't
    /// leave behind a palette action that jumps to a tab which no longer shows it.
    private var ledgerActions: [QuickActionItem] {
        var actions: [QuickActionItem] = []
        let user = appState.currentUser

        if ActivitySegment.expenses.isAvailable(for: user) {
            actions.append(
                QuickActionItem(id: "expense", title: "Expense", subtitle: "Add an expense", systemImage: "arrow.up", role: .standard) {
                    openLedgerForm(.expenses) {
                        Task {
                            await expensesVM.loadCategories(workspaceId: appState.activeWorkspace?.id ?? "")
                            showExpenseForm = true
                        }
                    }
                }
            )
        }
        if ActivitySegment.income.isAvailable(for: user) {
            actions.append(
                QuickActionItem(id: "income", title: "Income", subtitle: "Add income", systemImage: "arrow.down", role: .standard) {
                    openLedgerForm(.income) {
                        Task {
                            await incomeVM.loadCategories(workspaceId: appState.activeWorkspace?.id ?? "")
                            showIncomeForm = true
                        }
                    }
                }
            )
        }
        if ActivitySegment.savings.isAvailable(for: user) {
            actions.append(
                QuickActionItem(id: "savings", title: "Savings", subtitle: "Add savings", systemImage: "banknote", role: .standard) {
                    openLedgerForm(.savings) { prepareGlobalSavingsForm() }
                }
            )
        }
        return actions
    }

    /// Closes the palette and presents the form without changing the originating
    /// tab. This keeps dismissal returning users to where they started.
    private func openLedgerForm(_ segment: ActivitySegment, present: @escaping () -> Void) {
        setFabOpen(false)
        activitySegment = segment
        Task {
            try? await Task.sleep(nanoseconds: 320_000_000)
            present()
        }
    }

    // MARK: - Bottom bar

    @ViewBuilder
    private var bottomBar: some View {
        if #available(iOS 26, *) {
            glassBottomBar
        } else {
            legacyBottomBar
        }
    }

    @available(iOS 26, *)
    private var glassBottomBar: some View {
        HStack(spacing: 12) {
            FloatingTabBar(selected: $selectedTab, tabs: availableTabs)
                .frame(maxWidth: .infinity)
                .glassEffect(.regular.interactive(), in: Capsule())

            // Nothing left to create — the palette would open onto an empty card.
        }
    }

    private var legacyBottomBar: some View {
        HStack(spacing: 12) {
            FloatingTabBar(selected: $selectedTab, tabs: availableTabs)
                .frame(maxWidth: .infinity)
                .background(
                    Capsule()
                    .fill(Theme.surface2)
                        .shadow(color: .black.opacity(0.4), radius: 20, y: 8)
                )

        }
    }

    // MARK: - Tab content

    @ViewBuilder
    private var tabContent: some View {
        let wsId = appState.activeWorkspace?.id ?? ""
        switch selectedTab {
        case .home:
            DashboardView(workspaceId: wsId, onOpenCategories: {
                // The insights ticker still makes sense without the Categories
                // screen behind it, so it stays — only the jump goes away.
                guard CardsCategoriesSegment.categories.isAvailable(for: appState.currentUser) else { return }
                // Categories will live under Activity in the unified ledger.
                // Until then, keep this route independent of credit-card access.
                showCategories = true
            })
        case .activity:
            activityTabContent(workspaceId: wsId)
        case .savings:
            SavingsView(workspaceId: wsId, showForm: $showSavingsForm, embedded: false)
        case .cards:
            CardsRootView(
                workspaceId: wsId,
                canUsePayments: appState.currentUser?.has(.creditCards) == true
                    && appState.currentUser?.has(.cardPayments) == true
            )
        }
    }

    @ViewBuilder
    private func activityTabContent(workspaceId: String) -> some View {
        let user = appState.currentUser
        ActivityView(
            workspaceId: workspaceId,
            selectedSegment: $activitySegment,
            showExpenseForm: $showExpenseForm,
            showIncomeForm: $showIncomeForm,
            showSavingsForm: $showSavingsForm,
            expensesVM: expensesVM,
            incomeVM: incomeVM,
            savingsVM: savingsVM
        )
    }
}

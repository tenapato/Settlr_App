import SwiftUI

struct MainTabView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme
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
    @State private var launcherTask: Task<Void, Never>?

    var body: some View {
        ZStack(alignment: .bottom) {
            tabContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            bottomBar
                .padding(.trailing, quickActionItems.isEmpty ? 0 : 64)
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
        .onChange(of: launcherAccessSignature) { _, _ in reconcileFeaturePresenters() }
        .onDisappear { launcherTask?.cancel() }
        // Splitting starts at the camera, not at a form.
        .fullScreenCover(isPresented: splitScanPresentation) {
            SplitScanFlow(workspaceId: appState.activeWorkspace?.id ?? "") { outcome in
                guard appState.currentUser?.has(.billSplits) == true,
                      appState.activeWorkspace != nil else { return }
                // Only a split that reached the server has an id worth opening.
                // A queued one lands in the list's "Waiting to upload" section,
                // and deep-linking a local id would spin forever.
                if case .created(let split) = outcome { createdSplitId = split.id }
                showSplitList = true
            }
        }
        .sheet(isPresented: splitListPresentation) {
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
        .sheet(isPresented: categoriesPresentation) {
            CategoriesView(workspaceId: appState.activeWorkspace?.id ?? "")
        }
    }

    private func setFabOpen(_ open: Bool) {
        fabOpen = open
    }

    private var rootExpenseFormPresentation: Binding<Bool> {
        Binding(
            get: {
                expenseFeaturePresentation.wrappedValue && selectedTab != .activity
            },
            set: { expenseFeaturePresentation.wrappedValue = $0 }
        )
    }

    private var expenseFeaturePresentation: Binding<Bool> {
        guardedPresentation($showExpenseForm, feature: .expenses)
    }

    private var rootIncomeFormPresentation: Binding<Bool> {
        Binding(
            get: {
                incomeFeaturePresentation.wrappedValue && selectedTab != .activity
            },
            set: { incomeFeaturePresentation.wrappedValue = $0 }
        )
    }

    private var incomeFeaturePresentation: Binding<Bool> {
        guardedPresentation($showIncomeForm, feature: .income)
    }

    private var savingsFeaturePresentation: Binding<Bool> {
        guardedPresentation($showSavingsForm, feature: .savings)
    }

    private func guardedPresentation(_ source: Binding<Bool>, feature: AppFeature) -> Binding<Bool> {
        Binding(
            get: {
                source.wrappedValue
                    && appState.currentUser?.has(feature) == true
                    && !rootWorkspaceID.isEmpty
            },
            set: { requested in
                source.wrappedValue = requested
                    && appState.currentUser?.has(feature) == true
                    && !rootWorkspaceID.isEmpty
            }
        )
    }

    private var rootSavingsFormPresentation: Binding<Bool> {
        Binding(
            get: {
                savingsFeaturePresentation.wrappedValue
                    && selectedTab != .savings
                    && selectedTab != .activity
                    && savingsVM.loadedWorkspaceID == rootWorkspaceID
                    && savingsVM.accountsRequestIsSettled(for: rootWorkspaceID)
                    && savingsVM.hasLoadedAccounts
                    && !savingsVM.accounts.isEmpty
                    && savingsVM.accountsErrorMessage == nil
                    && appState.currentUser?.has(.savings) == true
                    && !rootWorkspaceID.isEmpty
            },
            set: { savingsFeaturePresentation.wrappedValue = $0 }
        )
    }

    private var rootWorkspaceID: String { appState.activeWorkspace?.id ?? "" }

    private var rootSavingsAccountsPresentation: Binding<Bool> {
        Binding(
            get: {
                showRootSavingsAccounts && selectedTab != .savings && selectedTab != .activity
                    && appState.currentUser?.has(.savings) == true
                    && !rootWorkspaceID.isEmpty
            },
            set: { showRootSavingsAccounts = $0 }
        )
    }

    private var categoriesPresentation: Binding<Bool> {
        Binding(
            get: {
                showCategories
                    && appState.currentUser?.has(.categories) == true
                    && !rootWorkspaceID.isEmpty
            },
            set: { showCategories = $0 }
        )
    }

    private var splitScanPresentation: Binding<Bool> {
        Binding(
            get: {
                showSplitScan
                    && appState.currentUser?.has(.billSplits) == true
                    && !rootWorkspaceID.isEmpty
            },
            set: { showSplitScan = $0 }
        )
    }

    private var splitListPresentation: Binding<Bool> {
        Binding(
            get: {
                showSplitList
                    && appState.currentUser?.has(.billSplits) == true
                    && !rootWorkspaceID.isEmpty
            },
            set: { showSplitList = $0 }
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

    private var launcherAccessSignature: String {
        let disabled = (appState.currentUser?.disabledFeatures ?? []).sorted().joined(separator: ",")
        return "\(appState.currentUser?.id ?? "signed-out")|\(appState.currentUser?.role ?? "member")|\(rootWorkspaceID)|\(disabled)"
    }

    private func reconcileSelectedTab() {
        reconcileFeaturePresenters()
        guard !availableTabs.contains(selectedTab) else { return }
        selectedTab = .home
        // An open palette may have been showing actions that just went away.
        if fabOpen { setFabOpen(false) }
    }

    private func reconcileFeaturePresenters() {
        launcherTask?.cancel()
        launcherTask = nil

        let user = appState.currentUser
        let hasWorkspace = !rootWorkspaceID.isEmpty
        if !hasWorkspace || user?.has(.expenses) != true { showExpenseForm = false }
        if !hasWorkspace || user?.has(.income) != true { showIncomeForm = false }
        if !hasWorkspace || user?.has(.savings) != true {
            showSavingsForm = false
            showRootSavingsAccounts = false
        }
        if !hasWorkspace || user?.has(.categories) != true { showCategories = false }
        if !hasWorkspace || user?.has(.billSplits) != true {
            showSplitScan = false
            showSplitList = false
            createdSplitId = nil
        }
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
                    scheduleLauncherAction(requiredFeature: .billSplits) { _, _ in
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
                    openLedgerForm(.expenses, requiredFeature: .expenses) { workspaceId, userId in
                        await expensesVM.loadCategories(workspaceId: workspaceId)
                        guard launcherContextIsValid(workspaceId: workspaceId, userId: userId, feature: .expenses) else { return }
                        showExpenseForm = true
                    }
                }
            )
        }
        if ActivitySegment.income.isAvailable(for: user) {
            actions.append(
                QuickActionItem(id: "income", title: "Income", subtitle: "Add income", systemImage: "arrow.down", role: .standard) {
                    openLedgerForm(.income, requiredFeature: .income) { workspaceId, userId in
                        await incomeVM.loadCategories(workspaceId: workspaceId)
                        guard launcherContextIsValid(workspaceId: workspaceId, userId: userId, feature: .income) else { return }
                        showIncomeForm = true
                    }
                }
            )
        }
        if ActivitySegment.savings.isAvailable(for: user) {
            actions.append(
                QuickActionItem(id: "savings", title: "Savings", subtitle: "Add savings", systemImage: "banknote", role: .standard) {
                    openLedgerForm(.savings, requiredFeature: .savings) { _, _ in prepareGlobalSavingsForm() }
                }
            )
        }
        return actions
    }

    /// Closes the palette and presents the form without changing the originating
    /// tab. This keeps dismissal returning users to where they started.
    private func openLedgerForm(
        _ segment: ActivitySegment,
        requiredFeature: AppFeature,
        present: @escaping @MainActor (_ workspaceId: String, _ userId: String) async -> Void
    ) {
        activitySegment = segment
        scheduleLauncherAction(requiredFeature: requiredFeature, action: present)
    }

    private func scheduleLauncherAction(
        requiredFeature: AppFeature,
        action: @escaping @MainActor (_ workspaceId: String, _ userId: String) async -> Void
    ) {
        setFabOpen(false)
        launcherTask?.cancel()
        guard let userId = appState.currentUser?.id,
              !rootWorkspaceID.isEmpty,
              appState.currentUser?.has(requiredFeature) == true else { return }
        let workspaceId = rootWorkspaceID
        launcherTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 320_000_000)
            guard !Task.isCancelled,
                  launcherContextIsValid(workspaceId: workspaceId, userId: userId, feature: requiredFeature) else { return }
            await action(workspaceId, userId)
        }
    }

    private func launcherContextIsValid(
        workspaceId: String,
        userId: String,
        feature: AppFeature
    ) -> Bool {
        appState.currentUser?.id == userId
            && appState.activeWorkspace?.id == workspaceId
            && appState.currentUser?.has(feature) == true
    }

    // MARK: - Bottom bar

    @ViewBuilder
    private var bottomBar: some View {
        FloatingTabBar(selected: $selectedTab, tabs: availableTabs)
            .frame(maxWidth: .infinity)
            .background(
                Capsule()
                    .fill(Theme.surface)
                    .overlay(Capsule().strokeBorder(Theme.line, lineWidth: 1))
                    .shadow(
                        color: .black.opacity(colorScheme == .dark ? 0.48 : 0.12),
                        radius: 20,
                        y: 8
                    )
            )
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
            showExpenseForm: expenseFeaturePresentation,
            showIncomeForm: incomeFeaturePresentation,
            showSavingsForm: savingsFeaturePresentation,
            expensesVM: expensesVM,
            incomeVM: incomeVM,
            savingsVM: savingsVM
        )
    }
}

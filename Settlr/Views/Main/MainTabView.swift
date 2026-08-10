import SwiftUI

struct MainTabView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedTab: Tab = .home
    @State private var cardsSegment: CardsCategoriesSegment = .cards
    @State private var activitySegment: ActivitySegment = .expenses
    // Held here, not in the leaf views, so the selected month survives navigation.
    @State private var expensesVM = ExpensesVM()
    @State private var incomeVM = IncomeVM()
    @State private var fabOpen = false
    @State private var showExpenseForm = false
    @State private var showIncomeForm = false
    @State private var showSavingsForm = false
    @State private var showSplitList = false
    @State private var showSplitScan = false
    @State private var createdSplitId: String?

    private let fabSpring = Animation.spring(response: 0.44, dampingFraction: 0.78)
    private let fabCloseSpring = Animation.spring(response: 0.36, dampingFraction: 0.86)

    var body: some View {
        ZStack(alignment: .bottom) {
            tabContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            fabBackdrop

            fabMenu
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(.trailing, 16)
                .padding(.bottom, 16 + 58 + 14)

            bottomBar
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
        }
        .background(Color(hex: "#0e0f11"))
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
    }

    private var fabBackdrop: some View {
        Color.black
            .opacity(fabOpen ? 0.55 : 0)
            .ignoresSafeArea()
            .allowsHitTesting(fabOpen)
            .onTapGesture { setFabOpen(false) }
            .animation(fabOpen ? fabSpring : fabCloseSpring, value: fabOpen)
    }

    private var fabMenu: some View {
        actionItems
            .opacity(fabOpen ? 1 : 0)
            .scaleEffect(fabOpen ? 1 : 0.7, anchor: .bottomTrailing)
            .offset(y: fabOpen ? 0 : 12)
            .blur(radius: fabOpen ? 0 : 4)
            .allowsHitTesting(fabOpen)
            .accessibilityHidden(!fabOpen)
            .animation(fabOpen ? fabSpring : fabCloseSpring, value: fabOpen)
    }

    private func setFabOpen(_ open: Bool) {
        withAnimation(open ? fabSpring : fabCloseSpring) {
            fabOpen = open
        }
    }

    // MARK: - Feature availability

    private var availableTabs: [Tab] { Tab.available(for: appState.currentUser) }

    private func reconcileSelectedTab() {
        guard !availableTabs.contains(selectedTab) else { return }
        selectedTab = .home
        // An open palette may have been showing actions that just went away.
        if fabOpen { setFabOpen(false) }
    }

    // MARK: - Action items

    /// One card, hairline dividers, a tinted glyph per row — the same surface
    /// treatment as every other card in the app, rather than a bespoke widget.
    /// Tiles-inside-a-card double-boxed each action and looked foreign here.
    private var actionItems: some View {
        VStack(spacing: 0) {
            ForEach(Array(quickActions.enumerated()), id: \.offset) { idx, action in
                if idx > 0 {
                    Rectangle()
                        .fill(Color(hex: "#2a2d32"))
                        .frame(height: 1)
                        .padding(.leading, 56)
                }
                PaletteActionRow(
                    label: action.label,
                    icon: action.icon,
                    color: action.color,
                    index: idx,
                    fabOpen: fabOpen,
                    onTap: action.handler
                )
            }
        }
        .frame(width: 216)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(hex: "#15171a"))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color(hex: "#2a2d32"), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.55), radius: 24, y: 10)
        )
    }

    private var fabButton: some View {
        Button { setFabOpen(!fabOpen) } label: {
            fabIcon
                .background(Circle().fill(fabOpen ? Color(hex: "#2a2d32") : Color(hex: "#c8ff5a")))
                .shadow(
                    color: (fabOpen ? Color.clear : Color(hex: "#c8ff5a")).opacity(0.3),
                    radius: 16,
                    y: 4
                )
        }
        .buttonStyle(.plain)
        .animation(fabOpen ? fabSpring : fabCloseSpring, value: fabOpen)
    }

    private struct QuickAction {
        let label: String
        /// One word, so labels don't collide along the arc.
        let shortLabel: String
        let icon: String
        let color: Color
        let handler: () -> Void
    }

    private var quickActions: [QuickAction] {
        var actions: [QuickAction] = []
        // Bill splitting lives only here — it is a one-off action, not a place
        // you navigate to, so it stays out of the tab bar.
        if appState.currentUser?.has(.billSplits) ?? false {
            // The pending count rides on the label because the split list lives
            // behind a sheet — without it, a split waiting to upload is
            // invisible until the user happens to go looking for it.
            let waiting = appState.currentUser.map { PendingSplitQueue.shared.pendingCount(userId: $0.id) } ?? 0
            actions.append(
                QuickAction(
                    label: waiting > 0 ? "Split a Bill (\(waiting) waiting)" : "Split a Bill",
                    shortLabel: "Split", icon: "doc.viewfinder", color: Color(hex: "#c8ff5a")
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
    private var ledgerActions: [QuickAction] {
        var actions: [QuickAction] = []
        let user = appState.currentUser

        if ActivitySegment.expenses.isAvailable(for: user) {
            actions.append(
                QuickAction(label: "Add Expense", shortLabel: "Expense", icon: "arrow.up", color: Color(hex: "#ff6b6b")) {
                    openLedgerForm(.expenses) { showExpenseForm = true }
                }
            )
        }
        if ActivitySegment.income.isAvailable(for: user) {
            actions.append(
                QuickAction(label: "Add Income", shortLabel: "Income", icon: "arrow.down", color: Color(hex: "#5ddf8a")) {
                    openLedgerForm(.income) { showIncomeForm = true }
                }
            )
        }
        if ActivitySegment.savings.isAvailable(for: user) {
            actions.append(
                QuickAction(label: "Add Savings", shortLabel: "Savings", icon: "banknote", color: Color(hex: "#22c55e")) {
                    openLedgerForm(.savings) { showSavingsForm = true }
                }
            )
        }
        return actions
    }

    /// Closes the palette, switches to the right segment, then presents the form
    /// once the close animation has cleared the screen.
    private func openLedgerForm(_ segment: ActivitySegment, present: @escaping () -> Void) {
        setFabOpen(false)
        selectedTab = .activity
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
            if !quickActions.isEmpty { fabButton }
        }
    }

    private var legacyBottomBar: some View {
        HStack(spacing: 12) {
            FloatingTabBar(selected: $selectedTab, tabs: availableTabs)
                .frame(maxWidth: .infinity)
                .background(
                    Capsule()
                        .fill(Color(hex: "#1c1f23"))
                        .shadow(color: .black.opacity(0.4), radius: 20, y: 8)
                )

            if !quickActions.isEmpty { fabButton }
        }
    }

    private var fabIcon: some View {
        Image(systemName: "plus")
            .font(.system(size: 22, weight: .bold))
            .foregroundStyle(fabOpen ? Color(hex: "#ecedee") : Color(hex: "#0e0f11"))
            .rotationEffect(.degrees(fabOpen ? 45 : 0))
            .frame(width: 58, height: 58)
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
                cardsSegment = .categories
                selectedTab = .cards
            })
        case .activity:
            ActivityView(
                workspaceId: wsId,
                selectedSegment: $activitySegment,
                showExpenseForm: $showExpenseForm,
                showIncomeForm: $showIncomeForm,
                showSavingsForm: $showSavingsForm,
                expensesVM: expensesVM,
                incomeVM: incomeVM
            )
        case .cards:
            CardsAndCategoriesView(workspaceId: wsId, selectedSegment: $cardsSegment)
        case .payments:
            CardPaymentsView(workspaceId: wsId)
        }
    }
}

// MARK: - Palette row

/// One action in the FAB palette. Glyph in a tinted disc, label beside it, the
/// whole row tappable — matching the card rows used elsewhere in the app.
private struct PaletteActionRow: View {
    let label: String
    let icon: String
    let color: Color
    let index: Int
    let fabOpen: Bool
    let onTap: () -> Void

    @State private var pressed = false

    // Top row leads on open so the palette unrolls downward toward the thumb.
    private var animation: Animation {
        fabOpen
            ? .spring(response: 0.34, dampingFraction: 0.78).delay(Double(index) * 0.03)
            : .spring(response: 0.24, dampingFraction: 0.92)
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.16))
                        .frame(width: 30, height: 30)
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(color)
                }
                Text(label)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color(hex: "#ecedee"))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 11)
            .background(pressed ? Color(hex: "#1c1f23") : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in pressed = true }
                .onEnded { _ in pressed = false }
        )
        .opacity(fabOpen ? 1 : 0)
        .offset(y: fabOpen ? 0 : -6)
        .animation(animation, value: fabOpen)
        .accessibilityLabel(label)
    }
}

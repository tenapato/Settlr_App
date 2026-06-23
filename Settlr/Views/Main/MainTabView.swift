import SwiftUI

struct MainTabView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedTab: Tab = .home
    @State private var fabOpen = false
    @State private var showExpenseForm = false
    @State private var showIncomeForm = false

    private let fabSpring = Animation.spring(response: 0.44, dampingFraction: 0.78)
    private let fabCloseSpring = Animation.spring(response: 0.36, dampingFraction: 0.86)

    var body: some View {
        ZStack(alignment: .bottom) {
            tabContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            fabBackdrop

            fabMenu
                .padding(.trailing, 16)
                .padding(.bottom, 16 + 58 + 20)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)

            bottomBar
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
        }
        .background(Color(hex: "#0e0f11"))
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
            .scaleEffect(fabOpen ? 1 : 0.88, anchor: .bottomTrailing)
            .offset(y: fabOpen ? 0 : 18)
            .blur(radius: fabOpen ? 0 : 6)
            .allowsHitTesting(fabOpen)
            .accessibilityHidden(!fabOpen)
            .animation(fabOpen ? fabSpring : fabCloseSpring, value: fabOpen)
    }

    private func setFabOpen(_ open: Bool) {
        withAnimation(open ? fabSpring : fabCloseSpring) {
            fabOpen = open
        }
    }

    // MARK: - Action items

    private var actionItems: some View {
        VStack(alignment: .trailing, spacing: 20) {
            ForEach(Array(quickActions.reversed().enumerated()), id: \.offset) { idx, action in
                ActionRow(
                    label: action.label,
                    icon: action.icon,
                    color: action.color,
                    index: idx,
                    totalCount: quickActions.count,
                    fabOpen: fabOpen,
                    onTap: action.handler
                )
            }
        }
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
        let icon: String
        let color: Color
        let handler: () -> Void
    }

    private var quickActions: [QuickAction] {
        [
            QuickAction(label: "Add Expense", icon: "arrow.down", color: Color(hex: "#ff6b6b")) {
                setFabOpen(false)
                selectedTab = .expenses
                Task {
                    try? await Task.sleep(nanoseconds: 320_000_000)
                    showExpenseForm = true
                }
            },
            QuickAction(label: "Add Income", icon: "arrow.up", color: Color(hex: "#5ddf8a")) {
                setFabOpen(false)
                selectedTab = .income
                Task {
                    try? await Task.sleep(nanoseconds: 320_000_000)
                    showIncomeForm = true
                }
            },
        ]
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
            FloatingTabBar(selected: $selectedTab)
                .frame(maxWidth: .infinity)
                .glassEffect(.regular.interactive(), in: Capsule())

            fabButton
        }
    }

    private var legacyBottomBar: some View {
        HStack(spacing: 12) {
            FloatingTabBar(selected: $selectedTab)
                .frame(maxWidth: .infinity)
                .background(
                    Capsule()
                        .fill(Color(hex: "#1c1f23"))
                        .shadow(color: .black.opacity(0.4), radius: 20, y: 8)
                )

            fabButton
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
        case .home:       DashboardView(workspaceId: wsId)
        case .cards:      CardsView(workspaceId: wsId)
        case .expenses:   ExpensesView(workspaceId: wsId, showForm: $showExpenseForm)
        case .income:     IncomeView(workspaceId: wsId, showForm: $showIncomeForm)
        case .categories: CategoriesView(workspaceId: wsId)
        }
    }
}

// MARK: - Action Row

private struct ActionRow: View {
    let label: String
    let icon: String
    let color: Color
    let index: Int
    let totalCount: Int
    let fabOpen: Bool
    let onTap: () -> Void

    // Bottom item (closest to FAB) leads on open; top item leads on close.
    private var openDelay: Double { Double(totalCount - 1 - index) * 0.06 }
    private var closeDelay: Double { Double(index) * 0.05 }

    private var rowAnimation: Animation {
        if fabOpen {
            return .spring(response: 0.46, dampingFraction: 0.74).delay(openDelay)
        }
        return .spring(response: 0.34, dampingFraction: 0.88).delay(closeDelay)
    }

    private var labelOffset: CGFloat { fabOpen ? 0 : 28 }
    private var buttonOffset: CGFloat { fabOpen ? 0 : CGFloat(index + 1) * 22 + 12 }
    private var buttonScale: CGFloat { fabOpen ? 1 : 0.45 }

    var body: some View {
        HStack(spacing: 16) {
            Text(label)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .opacity(fabOpen ? 1 : 0)
                .offset(x: labelOffset)
                .animation(rowAnimation, value: fabOpen)

            actionButton
                .scaleEffect(buttonScale, anchor: .center)
                .opacity(fabOpen ? 1 : 0)
                .offset(y: buttonOffset)
                .animation(rowAnimation, value: fabOpen)
        }
        .allowsHitTesting(fabOpen)
    }

    @ViewBuilder
    private var actionButton: some View {
        legacyActionButton
    }

    private var legacyActionButton: some View {
        Button(action: onTap) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.18))
                    .frame(width: 58, height: 58)
                    .overlay(Circle().strokeBorder(color.opacity(0.35), lineWidth: 1))
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(color)
            }
        }
    }
}

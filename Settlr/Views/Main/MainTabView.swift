import SwiftUI

struct MainTabView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedTab: Tab = .home
    @State private var fabOpen = false
    @State private var showExpenseForm = false
    @State private var showIncomeForm = false

    var body: some View {
        ZStack(alignment: .bottom) {
            tabContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Dim overlay
            if fabOpen {
                Color.black.opacity(0.6)
                    .ignoresSafeArea()
                    .onTapGesture { closeActions() }
                    .transition(.opacity)
                    .zIndex(1)
            }

            // Floating action items
            if fabOpen {
                actionItems
                    .zIndex(2)
            }

            // Bottom nav bar (always on top)
            bottomBar
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
                .zIndex(3)
        }
        .background(Color(hex: "#0e0f11"))
        .ignoresSafeArea(edges: .bottom)
        .animation(.easeOut(duration: 0.18), value: fabOpen)
    }

    // MARK: - Action items overlay

    private var actionItems: some View {
        VStack(alignment: .trailing, spacing: 20) {
            // Reversed so first action is at top; stagger goes bottom-to-top
            ForEach(Array(quickActions.reversed().enumerated()), id: \.offset) { idx, action in
                ActionRow(
                    label: action.label,
                    icon: action.icon,
                    color: action.color,
                    index: idx,
                    onTap: action.handler
                )
            }
        }
        // Align to right, sit above the bottom bar (58pt FAB + 16 bottom + 16 gap)
        .padding(.trailing, 16)
        .padding(.bottom, 16 + 58 + 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
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
                closeActions()
                selectedTab = .expenses
                Task {
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    showExpenseForm = true
                }
            },
            QuickAction(label: "Add Income", icon: "arrow.up", color: Color(hex: "#5ddf8a")) {
                closeActions()
                selectedTab = .income
                Task {
                    try? await Task.sleep(nanoseconds: 300_000_000)
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
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                FloatingTabBar(selected: $selectedTab)
                    .glassEffect(.regular, in: Capsule())

                Button(action: toggleFAB) { fabIcon }
                    .glassEffect(
                        fabOpen
                            ? .regular.tint(Color(hex: "#ecedee").opacity(0.25)).interactive()
                            : .regular.tint(Color(hex: "#c8ff5a").opacity(0.6)).interactive(),
                        in: .circle
                    )
            }
        }
    }

    private var legacyBottomBar: some View {
        HStack(spacing: 12) {
            FloatingTabBar(selected: $selectedTab)
                .background(
                    Capsule()
                        .fill(Color(hex: "#1c1f23"))
                        .shadow(color: .black.opacity(0.4), radius: 20, y: 8)
                )

            Button(action: toggleFAB) {
                fabIcon
                    .background(
                        Circle().fill(fabOpen ? Color(hex: "#2a2d32") : Color(hex: "#c8ff5a"))
                    )
                    .shadow(
                        color: (fabOpen ? Color.clear : Color(hex: "#c8ff5a")).opacity(0.3),
                        radius: 16, y: 4
                    )
            }
        }
    }

    private var fabIcon: some View {
        Image(systemName: fabOpen ? "xmark" : "plus")
            .font(.system(size: fabOpen ? 18 : 22, weight: .bold))
            .foregroundStyle(fabOpen ? Color(hex: "#ecedee") : Color(hex: "#0e0f11"))
            .frame(width: 58, height: 58)
            .animation(.snappy(duration: 0.25), value: fabOpen)
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

    // MARK: - Actions

    private func toggleFAB() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.72)) {
            fabOpen.toggle()
        }
    }

    private func closeActions() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.78)) {
            fabOpen = false
        }
    }
}

// MARK: - Action Row

private struct ActionRow: View {
    let label: String
    let icon: String
    let color: Color
    let index: Int
    let onTap: () -> Void

    @State private var appeared = false

    var body: some View {
        HStack(spacing: 16) {
            Text(label)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .opacity(appeared ? 1 : 0)
                .offset(x: appeared ? 0 : 12)

            actionButton
        }
        .onAppear {
            let delay = Double(index) * 0.06
            withAnimation(.spring(response: 0.4, dampingFraction: 0.68).delay(delay)) {
                appeared = true
            }
        }
        .onDisappear { appeared = false }
    }

    @ViewBuilder
    private var actionButton: some View {
        if #available(iOS 26, *) {
            glassActionButton
        } else {
            legacyActionButton
        }
    }

    @available(iOS 26, *)
    private var glassActionButton: some View {
        Button(action: onTap) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 58, height: 58)
        }
        .glassEffect(.regular.tint(color.opacity(0.35)).interactive(), in: .circle)
        .scaleEffect(appeared ? 1 : 0.4)
        .opacity(appeared ? 1 : 0)
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
        .scaleEffect(appeared ? 1 : 0.4)
        .opacity(appeared ? 1 : 0)
    }
}

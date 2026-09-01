import SwiftUI

struct DashboardView: View {
    let workspaceId: String
    var onOpenCategories: () -> Void = {}

    @Environment(AppState.self) private var appState
    @State private var vm = DashboardVM()
    @State private var annualVM = AnnualDashboardVM()
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()

                if rootPresentation == .coldLoading {
                    SettlrPulseLoadingView(
                        message: "Getting your workspace",
                        detail: "Loading balances and account access."
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity)
                } else {
                    dashboardScroll
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.18), value: rootPresentation)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(rootPresentation == .coldLoading ? .hidden : .visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(Theme.muted)
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
        }
        .task {
            await vm.load(workspaceId: workspaceId)
            await annualVM.load(workspaceId: workspaceId, year: selectedYear)
        }
        .onChange(of: vm.selectedMonth) { _, month in
            guard !vm.consumeMonthChangeReloadSuppression(for: month) else { return }
            Task {
                await vm.load(workspaceId: workspaceId)
                annualVM.invalidate()
                await annualVM.load(workspaceId: workspaceId, year: selectedYear)
            }
        }
    }

    private var dashboardScroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                DashboardWorkspaceHeader(
                    name: appState.activeWorkspace?.name ?? "Dashboard",
                    onSwitchWorkspace: { appState.activeWorkspace = nil }
                )
                .padding(.horizontal, 20)

                dashboardState

                Spacer().frame(height: 92)
            }
            .padding(.top, 12)
        }
        .refreshable {
            await vm.load(workspaceId: workspaceId)
            annualVM.invalidate()
            await annualVM.load(workspaceId: workspaceId, year: selectedYear)
        }
    }

    private var rootPresentation: DashboardRootPresentation {
        DashboardRootPresentation.resolve(
            hasSummary: vm.summary != nil,
            isLoading: vm.isLoading,
            hasError: vm.errorMessage != nil
        )
    }

    private var selectedYear: Int {
        Int(vm.selectedMonth.prefix(4)) ?? Calendar.current.component(.year, from: .now)
    }

    @ViewBuilder
    private var dashboardState: some View {
        if let summary = vm.summary {
            VStack(alignment: .leading, spacing: 14) {
                if vm.isLoading {
                    SignalTraceLoadingView(lastUpdated: vm.lastUpdated)
                        .padding(.horizontal, 20)
                }

                DashboardContent(
                    summary: summary,
                    previousSummary: vm.previousSummary,
                    months: annualVM.months,
                    selectedMonth: $vm.selectedMonth,
                    onOpenCategories: onOpenCategories
                )

                if let errorMessage = vm.errorMessage {
                    DashboardRecoveryCard(message: errorMessage, hasCachedData: true) {
                        Task { await vm.load(workspaceId: workspaceId) }
                    }
                    .padding(.horizontal, 20)
                }
            }
        } else if let errorMessage = vm.errorMessage {
            DashboardRecoveryCard(message: errorMessage, hasCachedData: false) {
                Task { await vm.load(workspaceId: workspaceId) }
            }
            .padding(.horizontal, 20)
        }
    }
}

// MARK: - Workspace header

private struct DashboardWorkspaceHeader: View {
    let name: String
    let onSwitchWorkspace: () -> Void

    var body: some View {
        HStack {
            Button(action: onSwitchWorkspace) {
                HStack(spacing: 10) {
                    Image("SettlrLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 24, height: 24)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 1) {
                        SectionEyebrow("WORKSPACE", color: Theme.faint)
                        Text(name)
                            .font(.headline)
                            .foregroundStyle(Theme.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }

                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.faint)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(name) workspace")
            .accessibilityHint("Switches to another workspace")

            Spacer(minLength: 0)
        }
    }
}

// MARK: - Home hierarchy

private struct DashboardContent: View {
    let summary: SummaryResponse
    let previousSummary: SummaryResponse?
    let months: [MonthDataPoint]
    @Binding var selectedMonth: String
    let onOpenCategories: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            AvailableBalanceHero(summary: summary, selectedMonth: $selectedMonth)
                .padding(.horizontal, 20)

            MoneyFlowTrace(summary: summary)
                .padding(.horizontal, 20)

            SpendingInsightsTicker(
                summary: summary,
                previous: previousSummary,
                months: months,
                onTap: onOpenCategories
            )

            MonthMovementCount(summary: summary)
                .padding(.horizontal, 20)
        }
    }
}

private struct AvailableBalanceHero: View {
    let summary: SummaryResponse
    @Binding var selectedMonth: String
    @ScaledMetric(relativeTo: .largeTitle) private var amountSize: CGFloat = 48

    private var isPositive: Bool { summary.availableCents >= 0 }
    private var amountColor: Color { isPositive ? Theme.ink : Theme.expense }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            MonthPickerRow(selectedMonth: $selectedMonth)
                .padding(.horizontal, -12)

            SectionEyebrow("AVAILABLE THIS MONTH")
            AmountLabel(
                cents: summary.availableCents,
                font: .system(size: amountSize, weight: .bold)
            )
            .foregroundStyle(amountColor)
            .contentTransition(.numericText(countsDown: summary.availableCents < 0))
            .lineLimit(1)
            .minimumScaleFactor(0.55)

            HStack(spacing: 7) {
                Circle()
                    .fill(isPositive ? Theme.accent : Theme.expense)
                    .frame(width: 6, height: 6)
                Text(isPositive ? "After savings" : "Below zero after savings")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Monthly money flow

private struct MoneyFlowTrace: View {
    let summary: SummaryResponse

    private var presentation: DashboardMoneyFlowPresentation {
        DashboardMoneyFlowPresentation(summary: summary)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionEyebrow("MONEY FLOW")
                .padding(.bottom, 10)

            ForEach(Array(presentation.entries.enumerated()), id: \.offset) { index, entry in
                HStack(spacing: 10) {
                    flowTrace(entry: entry, isLast: index == presentation.entries.count - 1)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(title(for: entry))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.ink)
                        Text(subtitle(for: entry.kind))
                            .font(.caption2)
                            .foregroundStyle(Theme.faint)
                    }

                    Spacer(minLength: 10)
                    signedAmount(entry.signedCents, color: color(for: entry))
                }
                .frame(minHeight: 44)
            }
        }
        .padding(.vertical, 14)
        .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) }
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
    }

    private func flowTrace(
        entry: DashboardMoneyFlowPresentation.Entry,
        isLast: Bool
    ) -> some View {
        VStack(spacing: 2) {
            Circle()
                .fill(Theme.bg)
                .overlay(Circle().strokeBorder(color(for: entry), lineWidth: 2))
                .frame(width: 8, height: 8)
            if !isLast {
                Rectangle()
                    .fill(Theme.line)
                    .frame(width: 1)
                    .frame(maxHeight: .infinity)
            }
        }
        .frame(width: 8)
        .frame(minHeight: 44)
    }

    private func signedAmount(_ cents: Int, color: Color) -> some View {
        HStack(spacing: 2) {
            if cents != 0 {
                Text(cents > 0 ? "+" : "−")
            }
            AmountLabel(
                cents: abs(cents),
                font: .subheadline.weight(.semibold),
                positive: cents > 0
            )
        }
        .foregroundStyle(color)
        .lineLimit(1)
        .minimumScaleFactor(0.65)
        .accessibilityElement(children: .combine)
    }

    private func title(for entry: DashboardMoneyFlowPresentation.Entry) -> String {
        switch entry.kind {
        case .income: "Came in"
        case .spending: "Went out"
        case .savings: entry.signedCents > 0 ? "Moved back" : "Moved aside"
        }
    }

    private func subtitle(for kind: DashboardMoneyFlowPresentation.Kind) -> String {
        switch kind {
        case .income: "Income"
        case .spending: "Spending"
        case .savings: "Savings"
        }
    }

    private func color(for entry: DashboardMoneyFlowPresentation.Entry) -> Color {
        switch entry.kind {
        case .income: Theme.income
        case .spending: Theme.expense
        case .savings: entry.signedCents > 0 ? Theme.income : Theme.accentText
        }
    }
}

private struct MonthMovementCount: View {
    let summary: SummaryResponse

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(summary.transactionCount) movements")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.ink)
            Text("this month")
                .font(.caption)
                .foregroundStyle(Theme.muted)
            Spacer(minLength: 8)
            Text("\(summary.expenseCount) out · \(summary.incomeCount) in")
                .font(.caption)
                .foregroundStyle(Theme.faint)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Recovery

private struct DashboardRecoveryCard: View {
    let message: String
    let hasCachedData: Bool
    let onRetry: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(Theme.warning)
            VStack(alignment: .leading, spacing: 3) {
                Text(hasCachedData ? "Couldn’t refresh Home" : "Couldn’t load Home")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                if hasCachedData {
                    Text("Saved Home data is still visible and may be out of date.")
                        .font(.caption)
                        .foregroundStyle(Theme.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(message)
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            Button("Retry", action: onRetry)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.accentText)
                .frame(minWidth: 44, minHeight: 44)
        }
        .padding(.horizontal, 12)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.line, lineWidth: 1))
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Month picker

private struct MonthPickerRow: View {
    @Binding var selectedMonth: String

    var body: some View {
        HStack(spacing: 8) {
            Button { selectedMonth = offset(by: -1) } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.muted)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Previous month")

            Button {
                let f = DateFormatter()
                f.dateFormat = "yyyy-MM"
                selectedMonth = f.string(from: Date())
            } label: {
                Text(displayMonth)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentTransition(.numericText())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Select month")
            .accessibilityValue(displayMonth)
            .accessibilityHint("Jump to the current month")

            Button { selectedMonth = offset(by: 1) } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.muted)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Next month")
        }
    }

    private var displayMonth: String {
        let parts = selectedMonth.split(separator: "-")
        guard parts.count == 2, let y = Int(parts[0]), let m = Int(parts[1]) else { return selectedMonth }
        var comps = DateComponents()
        comps.year = y
        comps.month = m
        comps.day = 1
        guard let date = Calendar.current.date(from: comps) else { return selectedMonth }
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        return f.string(from: date)
    }

    private func offset(by months: Int) -> String {
        let parts = selectedMonth.split(separator: "-")
        guard parts.count == 2, let y = Int(parts[0]), let m = Int(parts[1]) else { return selectedMonth }
        var comps = DateComponents()
        comps.year = y
        comps.month = m + months
        comps.day = 1
        guard let date = Calendar.current.date(from: comps) else { return selectedMonth }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM"
        return f.string(from: date)
    }
}

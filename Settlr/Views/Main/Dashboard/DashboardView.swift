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

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        DashboardWorkspaceHeader(
                            name: appState.activeWorkspace?.name ?? "Dashboard",
                            onSwitchWorkspace: { appState.activeWorkspace = nil }
                        )
                        .padding(.horizontal, 20)

                        MonthPickerRow(selectedMonth: $vm.selectedMonth)
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
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
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
        .onChange(of: vm.selectedMonth) { _, _ in
            Task {
                await vm.load(workspaceId: workspaceId)
                annualVM.invalidate()
                await annualVM.load(workspaceId: workspaceId, year: selectedYear)
            }
        }
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
                    onOpenCategories: onOpenCategories
                )

                if let errorMessage = vm.errorMessage {
                    DashboardRecoveryCard(message: errorMessage, hasCachedData: true) {
                        Task { await vm.load(workspaceId: workspaceId) }
                    }
                    .padding(.horizontal, 20)
                }
            }
        } else if vm.isLoading {
            SettlrPulseLoadingView(message: "Getting your workspace")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 56)
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
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                SectionEyebrow("WORKSPACE", color: Theme.faint)
                Text(name)
                    .font(.largeTitle.bold())
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }

            Button(action: onSwitchWorkspace) {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.muted)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Theme.surface2))
                    .overlay(Circle().strokeBorder(Theme.line, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .frame(width: 44, height: 44)
            .accessibilityLabel("Switch workspace")

            Spacer(minLength: 0)
        }
    }
}

// MARK: - Home hierarchy

private struct DashboardContent: View {
    let summary: SummaryResponse
    let previousSummary: SummaryResponse?
    let months: [MonthDataPoint]
    let onOpenCategories: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            AvailableBalanceHero(summary: summary)
                .padding(.horizontal, 20)

            FlowSummary(summary: summary)
                .padding(.horizontal, 20)

            SpendingInsightsTicker(
                summary: summary,
                previous: previousSummary,
                months: months,
                onTap: onOpenCategories
            )

            SpendingBreakdownCard(summary: summary)
                .padding(.horizontal, 20)

            RecentActivityPreview(summary: summary)
                .padding(.horizontal, 20)
        }
    }
}

private struct AvailableBalanceHero: View {
    let summary: SummaryResponse
    @ScaledMetric(relativeTo: .largeTitle) private var amountSize: CGFloat = 44

    private var isPositive: Bool { summary.availableCents >= 0 }
    private var amountColor: Color { isPositive ? Theme.accentText : Theme.expense }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionEyebrow("AVAILABLE THIS MONTH")
            AmountLabel(
                cents: summary.availableCents,
                font: .system(size: amountSize, weight: .bold, design: .rounded)
            )
            .foregroundStyle(amountColor)
            .contentTransition(.numericText(countsDown: summary.availableCents < 0))
            .lineLimit(1)
            .minimumScaleFactor(0.55)

            HStack(spacing: 7) {
                Circle()
                    .fill(amountColor)
                    .frame(width: 6, height: 6)
                Text(isPositive ? "After savings" : "Below zero after savings")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Income, spending, and saved summary

private struct FlowSummary: View {
    let summary: SummaryResponse

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Monthly movement")
                .font(.headline)
                .foregroundStyle(Theme.ink)

            HStack(spacing: 0) {
                SummaryMetric(label: "Income", cents: summary.incomeCents, color: Theme.income)
                summaryDivider
                SummaryMetric(label: "Spending", cents: summary.expenseCents, color: Theme.expense)
                summaryDivider
                SummaryMetric(label: "Saved", cents: summary.savingsNetCents, color: Theme.accentText)
            }
            .padding(.vertical, 14)
            .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) }
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
        }
    }

    private var summaryDivider: some View {
        Rectangle()
            .fill(Theme.line)
            .frame(width: 1, height: 36)
    }
}

private struct SummaryMetric: View {
    let label: String
    let cents: Int
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(Theme.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            AmountLabel(cents: cents, font: .subheadline.weight(.semibold))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.55)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
    }
}

// MARK: - Compact recent activity

private struct RecentActivityPreview: View {
    let summary: SummaryResponse

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recent activity")
                    .font(.headline)
                    .foregroundStyle(Theme.ink)
                Spacer()
                Text("This month")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Theme.faint)
            }

            HStack(spacing: 12) {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.accentText)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Theme.surface2))

                VStack(alignment: .leading, spacing: 3) {
                    Text(summary.transactionCount == 0 ? "No transactions yet" : "\(summary.transactionCount) transactions")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                    Text("\(summary.incomeCount) income · \(summary.expenseCount) spending")
                        .font(.footnote)
                        .foregroundStyle(Theme.muted)
                }
                Spacer(minLength: 0)
            }
            .frame(minHeight: 52)
        }
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

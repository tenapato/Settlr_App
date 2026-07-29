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
                Color(hex: "#0e0f11").ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        DashboardWorkspaceHeader(
                            name: appState.activeWorkspace?.name ?? "Dashboard",
                            onSwitchWorkspace: { appState.activeWorkspace = nil }
                        )
                        .padding(.horizontal, 16)

                        MonthPickerRow(selectedMonth: $vm.selectedMonth)
                            .padding(.horizontal, 24)

                        ZStack {
                            if vm.isLoading {
                                DashboardSkeleton()
                                    .transition(.opacity)
                            } else if let s = vm.summary {
                                DashboardContent(
                                    summary: s,
                                    previousSummary: vm.previousSummary,
                                    months: annualVM.months,
                                    onOpenCategories: onOpenCategories
                                )
                                .transition(.opacity)
                            } else if vm.errorMessage != nil {
                                ErrorCard(message: vm.errorMessage ?? "Something went wrong") {
                                    Task { await vm.load(workspaceId: workspaceId) }
                                }
                                .padding(.horizontal, 24)
                                .transition(.opacity)
                            }
                        }
                        .animation(.easeOut(duration: 0.25), value: vm.isLoading)

                        AnnualEvolutionChart(months: annualVM.months, isLoading: annualVM.isLoading && annualVM.months.isEmpty)
                            .padding(.horizontal, 24)

                        FinancialHealthCard()
                            .padding(.horizontal, 24)

                        Spacer().frame(height: 100)
                    }
                    .padding(.top, 8)
                }
                .refreshable {
                    await vm.load(workspaceId: workspaceId)
                    annualVM.invalidate()
                    let year = Int(vm.selectedMonth.prefix(4)) ?? Calendar.current.component(.year, from: .now)
                    await annualVM.load(workspaceId: workspaceId, year: year)
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape")
                            .foregroundStyle(Color(hex: "#8e9197"))
                    }
                }
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
        }
        .preferredColorScheme(.dark)
        .task {
            await vm.load(workspaceId: workspaceId)
            let year = Int(vm.selectedMonth.prefix(4)) ?? Calendar.current.component(.year, from: .now)
            await annualVM.load(workspaceId: workspaceId, year: year)
        }
        .onChange(of: vm.selectedMonth) { _, _ in
            Task {
                await vm.load(workspaceId: workspaceId)
                let year = Int(vm.selectedMonth.prefix(4)) ?? Calendar.current.component(.year, from: .now)
                await annualVM.load(workspaceId: workspaceId, year: year)
            }
        }
    }
}

// MARK: - Workspace header

private struct DashboardWorkspaceHeader: View {
    let name: String
    let onSwitchWorkspace: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(name)
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(Color(hex: "#ecedee"))

            Button(action: onSwitchWorkspace) {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(hex: "#8e9197"))
                    .frame(width: 32, height: 32)
                    .background(
                        Circle()
                            .fill(Color(hex: "#1c1f23"))
                            .overlay(
                                Circle()
                                    .strokeBorder(Color(hex: "#2a2d32"), lineWidth: 1)
                            )
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Switch workspace")

            Spacer(minLength: 0)
        }
    }
}

// MARK: - Content container (staggered entry)

private struct DashboardContent: View {
    let summary: SummaryResponse
    let previousSummary: SummaryResponse?
    let months: [MonthDataPoint]
    let onOpenCategories: () -> Void
    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SpendingInsightsTicker(
                summary: summary,
                previous: previousSummary,
                months: months,
                onTap: onOpenCategories
            )
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 18)

            BalanceHero(summary: summary)
                .padding(.horizontal, 24)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 18)

            FlowSummary(summary: summary)
                .padding(.horizontal, 24)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 18)
        }
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.82)) {
                appeared = true
            }
        }
        .onDisappear { appeared = false }
    }
}

// MARK: - Balance Hero (net balance + transaction counts, one card)

private struct BalanceHero: View {
    let summary: SummaryResponse

    private var isPositive: Bool { summary.netCents >= 0 }
    private var accentColor: Color {
        isPositive ? Color(hex: "#c8ff5a") : Color(hex: "#ff6b6b")
    }

    var body: some View {
        VStack(spacing: 0) {
            balanceSection

            Rectangle()
                .fill(Color(hex: "#2a2d32"))
                .frame(height: 1)

            CounterRow(
                transactionCount: summary.transactionCount,
                incomeCount: summary.incomeCount,
                expenseCount: summary.expenseCount
            )
        }
        .background(
            ZStack {
                Color(hex: "#15171a")
                RadialGradient(
                    colors: [accentColor.opacity(0.10), .clear],
                    center: .bottomTrailing,
                    startRadius: 0,
                    endRadius: 260
                )
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(Color(hex: "#2a2d32"), lineWidth: 1)
        )
    }

    private var balanceSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Net Balance")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color(hex: "#8e9197"))
                .tracking(1.4)
                .textCase(.uppercase)

            // `lineLimit(1)` + scaling keeps long values like "MXN $1,554.00" on a single line;
            // at the previous 40pt they wrapped mid-value onto two lines.
            AmountLabel(
                cents: summary.netCents,
                font: .system(size: 36, weight: .bold, design: .rounded)
            )
            .foregroundStyle(accentColor)
            .contentTransition(.numericText(countsDown: summary.netCents < 0))
            .lineLimit(1)
            .minimumScaleFactor(0.6)

            HStack(spacing: 7) {
                Circle()
                    .fill(accentColor)
                    .frame(width: 6, height: 6)
                Text(isPositive ? "Positive balance" : "Deficit")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(accentColor.opacity(0.7))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
    }
}

private struct CounterRow: View {
    let transactionCount: Int
    let incomeCount: Int
    let expenseCount: Int

    var body: some View {
        HStack(spacing: 0) {
            CounterCell(
                value: transactionCount,
                label: "Transactions",
                color: Color(hex: "#c8ff5a")
            )

            counterDivider

            CounterCell(
                value: incomeCount,
                label: "Income",
                color: Color(hex: "#5ddf8a")
            )

            counterDivider

            CounterCell(
                value: expenseCount,
                label: "Expenses",
                color: Color(hex: "#ff6b6b")
            )
        }
    }

    private var counterDivider: some View {
        Rectangle()
            .fill(Color(hex: "#2a2d32"))
            .frame(width: 1, height: 36)
    }
}

private struct CounterCell: View {
    let value: Int
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text("\(value)")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(color)
                .contentTransition(.numericText())
                .monospacedDigit()

            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color(hex: "#8e9197"))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
    }
}

// MARK: - Flow Summary

private struct FlowSummary: View {
    let summary: SummaryResponse
    @State private var animatedRatio: Double = 0

    private var total: Int { summary.incomeCents + summary.expenseCents }
    private var targetRatio: Double {
        guard total > 0 else { return 0.5 }
        return Double(summary.incomeCents) / Double(total)
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                FlowCard(label: "Income",   cents: summary.incomeCents,  icon: "arrow.down", color: Color(hex: "#5ddf8a"))
                FlowCard(label: "Expenses", cents: summary.expenseCents, icon: "arrow.up",   color: Color(hex: "#ff6b6b"))
            }

            if total > 0 {
                VStack(spacing: 6) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color(hex: "#ff6b6b").opacity(0.2))
                                .frame(height: 5)
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [Color(hex: "#5ddf8a"), Color(hex: "#c8ff5a")],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: max(8, geo.size.width * animatedRatio), height: 5)
                        }
                    }
                    .frame(height: 5)

                    HStack {
                        Text("Income \(Int(animatedRatio * 100))%")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color(hex: "#5ddf8a"))
                            .contentTransition(.numericText())
                        Spacer()
                        Text("Spent \(Int((1 - animatedRatio) * 100))%")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color(hex: "#ff6b6b"))
                            .contentTransition(.numericText(countsDown: true))
                    }
                }
                .padding(.horizontal, 2)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.85).delay(0.12)) {
                animatedRatio = targetRatio
            }
        }
        .onChange(of: targetRatio) { _, new in
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                animatedRatio = new
            }
        }
    }
}

private struct FlowCard: View {
    let label: String
    let cents: Int
    let icon: String
    let color: Color

    // Icon and label share a compact top row so the amount gets the card's full inner width.
    // Side-by-side, a 38pt icon left only ~90pt for the number, which forced "MXN $2,077.00"
    // down to its `minimumScaleFactor` floor and looked squeezed.
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.12))
                        .frame(width: 26, height: 26)
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(color)
                }
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color(hex: "#8e9197"))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }

            AmountLabel(cents: cents, font: .system(size: 17, weight: .semibold))
                .foregroundStyle(Color(hex: "#ecedee"))
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(hex: "#15171a"))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Color(hex: "#2a2d32"), lineWidth: 1)
                )
        )
    }
}

// MARK: - Skeleton

private struct DashboardSkeleton: View {
    @State private var phase: CGFloat = 0

    var body: some View {
        VStack(spacing: 20) {
            SkeletonRect(cornerRadius: 4, height: 20)
                .padding(.horizontal, 24)

            SkeletonRect(cornerRadius: 20, height: 200)
                .padding(.horizontal, 24)

            HStack(spacing: 10) {
                SkeletonRect(cornerRadius: 16, height: 84)
                SkeletonRect(cornerRadius: 16, height: 84)
            }
            .padding(.horizontal, 24)

            SkeletonRect(cornerRadius: 16, height: 20)
                .padding(.horizontal, 24)
        }
    }
}

private struct SkeletonRect: View {
    let cornerRadius: CGFloat
    let height: CGFloat
    @State private var on = false

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(Color(hex: "#2a2d32").opacity(on ? 0.4 : 0.9))
            .frame(height: height)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    on = true
                }
            }
    }
}

// MARK: - Error

private struct ErrorCard: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 28))
                .foregroundStyle(Color(hex: "#ffb547"))
            Text(message)
                .font(.system(size: 14))
                .foregroundStyle(Color(hex: "#8e9197"))
                .multilineTextAlignment(.center)
            Button("Try Again", action: onRetry)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color(hex: "#c8ff5a"))
        }
        .frame(maxWidth: .infinity)
        .padding(32)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(hex: "#15171a"))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color(hex: "#2a2d32"), lineWidth: 1))
        )
    }
}

// MARK: - Month Picker

private struct MonthPickerRow: View {
    @Binding var selectedMonth: String

    var body: some View {
        HStack(spacing: 16) {
            Button { selectedMonth = offset(by: -1) } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(hex: "#8e9197"))
            }
            Button {
                let f = DateFormatter(); f.dateFormat = "yyyy-MM"
                selectedMonth = f.string(from: Date())
            } label: {
                Text(displayMonth)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color(hex: "#ecedee"))
                    .frame(maxWidth: .infinity)
                    .contentTransition(.numericText())
                    .animation(.snappy(duration: 0.2), value: selectedMonth)
            }
            .buttonStyle(.plain)
            Button { selectedMonth = offset(by: 1) } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(hex: "#8e9197"))
            }
        }
    }

    private var displayMonth: String {
        let parts = selectedMonth.split(separator: "-")
        guard parts.count == 2, let y = Int(parts[0]), let m = Int(parts[1]) else { return selectedMonth }
        var comps = DateComponents(); comps.year = y; comps.month = m; comps.day = 1
        guard let date = Calendar.current.date(from: comps) else { return selectedMonth }
        let f = DateFormatter(); f.dateFormat = "MMMM yyyy"
        return f.string(from: date)
    }

    private func offset(by months: Int) -> String {
        let parts = selectedMonth.split(separator: "-")
        guard parts.count == 2, let y = Int(parts[0]), let m = Int(parts[1]) else { return selectedMonth }
        var comps = DateComponents(); comps.year = y; comps.month = m + months; comps.day = 1
        guard let date = Calendar.current.date(from: comps) else { return selectedMonth }
        let f = DateFormatter(); f.dateFormat = "yyyy-MM"
        return f.string(from: date)
    }
}

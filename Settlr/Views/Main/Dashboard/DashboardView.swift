import SwiftUI

struct DashboardView: View {
    let workspaceId: String
    @Environment(AppState.self) private var appState
    @State private var vm = DashboardVM()
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "#0e0f11").ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        MonthPickerRow(selectedMonth: $vm.selectedMonth)
                            .padding(.horizontal, 24)

                        ZStack {
                            if vm.isLoading {
                                DashboardSkeleton()
                                    .transition(.opacity)
                            } else if let s = vm.summary {
                                DashboardContent(summary: s)
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

                        Spacer().frame(height: 100)
                    }
                    .padding(.top, 8)
                }
                .refreshable { await vm.load(workspaceId: workspaceId) }
            }
            .navigationTitle(appState.activeWorkspace?.name ?? "Dashboard")
            .navigationBarTitleDisplayMode(.large)
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
        .task { await vm.load(workspaceId: workspaceId) }
        .onChange(of: vm.selectedMonth) { _, _ in
            Task { await vm.load(workspaceId: workspaceId) }
        }
    }
}

// MARK: - Content container (staggered entry)

private struct DashboardContent: View {
    let summary: SummaryResponse
    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            BalanceHero(summary: summary)
                .padding(.horizontal, 24)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 18)

            FlowSummary(summary: summary)
                .padding(.horizontal, 24)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 18)

            if !summary.expensesByCategory.isEmpty {
                TopCategories(summary: summary)
                    .padding(.horizontal, 24)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 18)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.82)) {
                appeared = true
            }
        }
        .onDisappear { appeared = false }
    }
}

// MARK: - Balance Hero

private struct BalanceHero: View {
    let summary: SummaryResponse

    private var isPositive: Bool { summary.netCents >= 0 }
    private var accentColor: Color {
        isPositive ? Color(hex: "#c8ff5a") : Color(hex: "#ff6b6b")
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(hex: "#15171a"))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .strokeBorder(Color(hex: "#2a2d32"), lineWidth: 1)
                )

            RadialGradient(
                colors: [accentColor.opacity(0.10), .clear],
                center: .bottomTrailing,
                startRadius: 0,
                endRadius: 220
            )
            .clipShape(RoundedRectangle(cornerRadius: 20))

            VStack(alignment: .leading, spacing: 20) {
                Text("Net Balance")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(hex: "#8e9197"))
                    .tracking(1.4)
                    .textCase(.uppercase)

                VStack(alignment: .leading, spacing: 8) {
                    AmountLabel(
                        cents: summary.netCents,
                        font: .system(size: 40, weight: .bold, design: .rounded)
                    )
                    .foregroundStyle(accentColor)
                    .contentTransition(.numericText(countsDown: summary.netCents < 0))

                    HStack(spacing: 7) {
                        Circle()
                            .fill(accentColor)
                            .frame(width: 6, height: 6)
                        Text(isPositive ? "Positive balance" : "Deficit")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(accentColor.opacity(0.7))
                    }
                }
            }
            .padding(24)
        }
        .fixedSize(horizontal: false, vertical: true)
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
            HStack(spacing: 10) {
                FlowCard(label: "Income",   cents: summary.incomeCents,  icon: "arrow.up",   color: Color(hex: "#5ddf8a"))
                FlowCard(label: "Expenses", cents: summary.expenseCents, icon: "arrow.down", color: Color(hex: "#ff6b6b"))
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

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.12))
                    .frame(width: 38, height: 38)
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(color)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color(hex: "#8e9197"))
                AmountLabel(cents: cents, font: .system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(hex: "#ecedee"))
                    .contentTransition(.numericText())
            }
            Spacer()
        }
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

// MARK: - Top Categories

private struct TopCategories: View {
    let summary: SummaryResponse

    private var cats: [CategorySummary] { Array(summary.expensesByCategory.prefix(5)) }
    private var maxCents: Int { cats.map(\.totalCents).max() ?? 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Top Categories")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color(hex: "#8e9197"))
                .tracking(1.4)
                .textCase(.uppercase)

            VStack(spacing: 0) {
                ForEach(Array(cats.enumerated()), id: \.element.id) { i, cat in
                    CategoryRow(cat: cat, maxCents: maxCents, rank: i)
                    if i < cats.count - 1 {
                        Divider()
                            .background(Color(hex: "#2a2d32"))
                            .padding(.leading, 18)
                    }
                }
            }
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
}

private struct CategoryRow: View {
    let cat: CategorySummary
    let maxCents: Int
    let rank: Int
    @State private var animatedRatio: Double = 0

    private var targetRatio: Double {
        guard maxCents > 0 else { return 0 }
        return Double(cat.totalCents) / Double(maxCents)
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text(cat.categoryName ?? "Uncategorized")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color(hex: "#ecedee"))
                Spacer()
                AmountLabel(cents: cat.totalCents, font: .system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(hex: "#8e9197"))
                    .contentTransition(.numericText(countsDown: true))
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color(hex: "#2a2d32"))
                        .frame(height: 3)
                    Capsule()
                        .fill(Color(hex: "#ff6b6b").opacity(0.75))
                        .frame(width: max(6, geo.size.width * animatedRatio), height: 3)
                }
            }
            .frame(height: 3)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .onAppear {
            let delay = 0.15 + Double(rank) * 0.07
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8).delay(delay)) {
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

// MARK: - Skeleton

private struct DashboardSkeleton: View {
    @State private var phase: CGFloat = 0

    var body: some View {
        VStack(spacing: 20) {
            SkeletonRect(cornerRadius: 20, height: 130)
                .padding(.horizontal, 24)

            HStack(spacing: 10) {
                SkeletonRect(cornerRadius: 16, height: 76)
                SkeletonRect(cornerRadius: 16, height: 76)
            }
            .padding(.horizontal, 24)

            VStack(spacing: 0) {
                ForEach(0..<4, id: \.self) { i in
                    SkeletonRect(cornerRadius: 4, height: 12)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 18)
                    if i < 3 {
                        Divider().background(Color(hex: "#2a2d32"))
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(hex: "#15171a"))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color(hex: "#2a2d32"), lineWidth: 1))
            )
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

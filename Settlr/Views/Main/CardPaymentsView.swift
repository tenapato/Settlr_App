import SwiftUI
import Observation

// MARK: - ViewModel

@Observable
final class CardPaymentsVM {
    var month: String = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM"
        return f.string(from: Date())
    }()
    var fortnight: FortnightFilter = .all
    var summary: CardPaymentsSummaryResponse?
    var fortnightCards: [FortnightCard]?
    var isLoading = false
    var errorMessage: String?
    var busyCardId: String?

    private let api = APIClient.shared

    var activeWindow: FortnightWindow? {
        guard fortnight != .all else { return nil }
        return CardPaymentFortnight.window(
            reference: CardPaymentFortnight.referenceDay(forMonth: month),
            which: fortnight
        )
    }

    var visibleCards: [FortnightCard] {
        if fortnight == .all {
            return (summary?.creditCards ?? []).map {
                FortnightCard(row: $0, resolvedDueMonthKey: month)
            }
        }
        return fortnightCards ?? []
    }

    var displayTotals: CardPaymentsTotals? {
        if fortnight == .all { return summary?.totals }
        guard let cards = fortnightCards else { return nil }
        var due = 0
        var recorded = 0
        var remaining = 0
        for c in cards {
            due += c.row.paymentDueCents
            recorded += c.row.paymentsRecordedCents
            if !c.row.paidInFull {
                remaining += max(0, c.row.paymentDueCents - c.row.paymentsRecordedCents)
            }
        }
        return CardPaymentsTotals(
            totalPaymentDueCents: due,
            totalPaymentsRecordedCents: recorded,
            remainingDueCents: remaining,
            afterCardPaymentsCents: 0
        )
    }

    @MainActor
    func load(workspaceId: String) async {
        isLoading = visibleCards.isEmpty
        errorMessage = nil
        defer { isLoading = false }
        do {
            if let window = activeWindow {
                let prevMonth = CardPaymentFortnight.shiftMonth(window.monthKey, by: -1)
                async let currentResp: CardPaymentsSummaryResponse = api.fetch(
                    Endpoints.cardPaymentsSummary(workspaceId) + MonthRangeQuery.summaryQuery(month: window.monthKey)
                )
                async let previousResp: CardPaymentsSummaryResponse = api.fetch(
                    Endpoints.cardPaymentsSummary(workspaceId) + MonthRangeQuery.summaryQuery(month: prevMonth)
                )
                let (current, previous) = try await (currentResp, previousResp)
                fortnightCards = CardPaymentFortnight.mergeCards(
                    window: window,
                    currentMonthCards: current.creditCards,
                    previousMonthCards: previous.creditCards
                )
            } else {
                fortnightCards = nil
                summary = try await api.fetch(
                    Endpoints.cardPaymentsSummary(workspaceId) + MonthRangeQuery.summaryQuery(month: month)
                )
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    func setPaid(_ paid: Bool, workspaceId: String, cardId: String) async {
        // A fortnight-filtered card can belong to a different statement month
        // than the viewed one; writes must target the resolved month or they
        // silently hit the wrong record.
        let targetMonth = visibleCards.first(where: { $0.id == cardId })?.resolvedDueMonthKey ?? month
        busyCardId = cardId
        defer { busyCardId = nil }
        do {
            let path = paid
                ? Endpoints.markCardPaid(workspaceId, cardId)
                : Endpoints.unmarkCardPaid(workspaceId, cardId)
            let _: MarkCardPaidResponse = try await api.fetch(path, method: "POST", body: MarkCardPaidBody(month: targetMonth))
            await load(workspaceId: workspaceId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - View

struct CardPaymentsView: View {
    let workspaceId: String
    @State private var vm = CardPaymentsVM()

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "#0e0f11").ignoresSafeArea()

                VStack(spacing: 0) {
                    MonthSelectorBar(selectedMonth: $vm.month) {
                        Task { await vm.load(workspaceId: workspaceId) }
                    }
                    .padding(.horizontal, 20)

                    FortnightFilterBar(
                        selected: vm.fortnight,
                        options: fortnightOptions
                    ) { next in
                        vm.fortnight = next
                        Task { await vm.load(workspaceId: workspaceId) }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)

                    content
                }
            }
            .navigationTitle("Payments")
            .navigationBarTitleDisplayMode(.large)
        }
        .preferredColorScheme(.dark)
        .task { await vm.load(workspaceId: workspaceId) }
    }

    private var fortnightOptions: [(FortnightFilter, String)] {
        let ref = CardPaymentFortnight.referenceDay(forMonth: vm.month)
        return FortnightFilter.allCases.map { f in
            if f == .all { return (f, "All cards") }
            return (f, CardPaymentFortnight.window(reference: ref, which: f)?.label ?? "—")
        }
    }

    @ViewBuilder
    private var content: some View {
        if vm.isLoading {
            ProgressView()
                .tint(Color(hex: "#c8ff5a"))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let err = vm.errorMessage, vm.visibleCards.isEmpty {
            PaymentsErrorView(message: err) {
                Task { await vm.load(workspaceId: workspaceId) }
            }
        } else if vm.visibleCards.isEmpty {
            if vm.fortnight == .all {
                PaymentsEmptyView()
            } else {
                FortnightEmptyView(windowLabel: vm.activeWindow?.label ?? "this fortnight") {
                    vm.fortnight = .all
                    Task { await vm.load(workspaceId: workspaceId) }
                }
            }
        } else {
            loadedList
        }
    }

    private var loadedList: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                if let err = vm.errorMessage {
                    Text(err)
                        .font(.system(size: 13))
                        .foregroundStyle(Color(hex: "#ff6b6b"))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                }

                if let totals = vm.displayTotals {
                    TotalsStrip(totals: totals)
                        .padding(.horizontal, 20)
                }

                if let window = vm.activeWindow {
                    Text("Payment dates \(window.startDay)–\(window.endDay) · \(monthLabel(window.monthKey)). Cards without a cutoff or payment day are hidden.")
                        .font(.system(size: 11))
                        .foregroundStyle(Color(hex: "#5a5d63"))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                }

                ForEach(vm.visibleCards) { card in
                    CardPaymentTile(
                        row: card.row,
                        month: card.resolvedDueMonthKey,
                        busy: vm.busyCardId == card.row.creditCardId,
                        anyBusy: vm.busyCardId != nil
                    ) { paid in
                        Task { await vm.setPaid(paid, workspaceId: workspaceId, cardId: card.row.creditCardId) }
                    }
                    .padding(.horizontal, 20)
                }

                Spacer().frame(height: 100)
            }
            .padding(.top, 8)
        }
        .scrollContentBackground(.hidden)
        .refreshable { await vm.load(workspaceId: workspaceId) }
    }

    private func monthLabel(_ monthKey: String) -> String {
        let parts = monthKey.split(separator: "-")
        guard parts.count == 2, let y = Int(parts[0]), let m = Int(parts[1]) else { return monthKey }
        var comps = DateComponents(); comps.year = y; comps.month = m; comps.day = 1
        guard let date = Calendar.current.date(from: comps) else { return monthKey }
        let f = DateFormatter(); f.dateFormat = "MMMM yyyy"
        return f.string(from: date)
    }
}

// MARK: - Fortnight filter bar

private struct FortnightFilterBar: View {
    let selected: FortnightFilter
    let options: [(FortnightFilter, String)]
    let onSelect: (FortnightFilter) -> Void

    var body: some View {
        HStack {
            Menu {
                ForEach(options, id: \.0) { value, label in
                    Button {
                        onSelect(value)
                    } label: {
                        if value == selected {
                            Label(label, systemImage: "checkmark")
                        } else {
                            Text(label)
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .font(.system(size: 13, weight: .medium))
                    Text(selectedLabel)
                        .font(.system(size: 13, weight: .semibold))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                }
                .foregroundStyle(selected == .all ? Color(hex: "#8e9197") : Color(hex: "#c8ff5a"))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(Color(hex: "#15171a"))
                        .overlay(
                            Capsule().strokeBorder(
                                selected == .all ? Color(hex: "#2a2d32") : Color(hex: "#c8ff5a").opacity(0.4),
                                lineWidth: 1
                            )
                        )
                )
            }
            Spacer()
        }
    }

    private var selectedLabel: String {
        options.first(where: { $0.0 == selected })?.1 ?? "All cards"
    }
}

// MARK: - Month selector

private struct MonthSelectorBar: View {
    @Binding var selectedMonth: String
    let onChanged: () -> Void

    var body: some View {
        HStack {
            Button { change(by: -1) } label: {
                Image(systemName: "chevron.left")
                    .foregroundStyle(Color(hex: "#8e9197"))
            }
            Spacer()
            Button {
                let f = DateFormatter(); f.dateFormat = "yyyy-MM"
                selectedMonth = f.string(from: Date())
                onChanged()
            } label: {
                Text(displayLabel)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(hex: "#ecedee"))
                    .contentTransition(.numericText())
                    .animation(.snappy(duration: 0.2), value: selectedMonth)
            }
            .buttonStyle(.plain)
            Spacer()
            Button { change(by: 1) } label: {
                Image(systemName: "chevron.right")
                    .foregroundStyle(Color(hex: "#8e9197"))
            }
        }
        .padding(.vertical, 12)
    }

    private var displayLabel: String {
        let parts = selectedMonth.split(separator: "-")
        guard parts.count == 2, let y = Int(parts[0]), let m = Int(parts[1]) else { return selectedMonth }
        var comps = DateComponents(); comps.year = y; comps.month = m; comps.day = 1
        guard let date = Calendar.current.date(from: comps) else { return selectedMonth }
        let f = DateFormatter(); f.dateFormat = "MMMM yyyy"
        return f.string(from: date)
    }

    private func change(by delta: Int) {
        let parts = selectedMonth.split(separator: "-")
        guard parts.count == 2, let y = Int(parts[0]), let m = Int(parts[1]) else { return }
        var comps = DateComponents(); comps.year = y; comps.month = m + delta; comps.day = 1
        guard let date = Calendar.current.date(from: comps) else { return }
        let f = DateFormatter(); f.dateFormat = "yyyy-MM"
        selectedMonth = f.string(from: date)
        onChanged()
    }
}

// MARK: - Totals strip

private struct TotalsStrip: View {
    let totals: CardPaymentsTotals

    var body: some View {
        HStack(spacing: 0) {
            totalCell(label: "To pay", cents: totals.totalPaymentDueCents, color: Color(hex: "#ff6b6b"))
            divider
            totalCell(label: "Recorded", cents: totals.totalPaymentsRecordedCents, color: Color(hex: "#ecedee"))
            divider
            totalCell(label: "Still owed", cents: totals.remainingDueCents, color: Color(hex: "#ffb547"))
        }
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(hex: "#15171a"))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color(hex: "#2a2d32"), lineWidth: 1))
        )
    }

    private var divider: some View {
        Rectangle()
            .fill(Color(hex: "#2a2d32"))
            .frame(width: 1, height: 32)
    }

    private func totalCell(label: String, cents: Int, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color(hex: "#8e9197"))
                .tracking(0.5).textCase(.uppercase)
            AmountLabel(cents: cents, font: .system(size: 14, weight: .semibold))
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Card tile

private struct CardPaymentTile: View {
    let row: CardPaymentRow
    let month: String
    let busy: Bool
    let anyBusy: Bool
    let onSetPaid: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(row.label)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color(hex: "#ecedee"))
                    Text(maskedNumber)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Color(hex: "#5a5d63"))
                }
                Spacer()
                statusTag
            }

            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("To pay")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color(hex: "#8e9197"))
                        .tracking(0.5).textCase(.uppercase)
                    AmountLabel(cents: row.paymentDueCents, font: .system(size: 22, weight: .bold))
                        .foregroundStyle(Color(hex: "#ecedee"))
                    if row.dueSource == "override" {
                        Text("Statement override · spend \(moneyString(row.spentCents))")
                            .font(.system(size: 11))
                            .foregroundStyle(Color(hex: "#5a5d63"))
                    }
                }
                Spacer()
                if let due = paymentDueDateLabel {
                    VStack(alignment: .trailing, spacing: 3) {
                        Text("Due")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color(hex: "#8e9197"))
                            .tracking(0.5).textCase(.uppercase)
                        Text(due)
                            .font(.system(size: 14, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Color(hex: "#c8ff5a"))
                    }
                }
            }

            HStack(spacing: 16) {
                miniStat(label: "Recorded", cents: row.paymentsRecordedCents)
                miniStat(label: "Still owed", cents: row.paidInFull ? nil : row.outstandingCents)
                if let pct = row.utilizationPct {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Usage")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color(hex: "#8e9197"))
                            .tracking(0.5).textCase(.uppercase)
                        Text(String(format: pct.truncatingRemainder(dividingBy: 1) == 0 ? "%.0f%%" : "%.1f%%", pct))
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .foregroundStyle(utilizationColor)
                    }
                }
                Spacer()
            }

            Button {
                onSetPaid(!row.paidInFull)
            } label: {
                Group {
                    if busy {
                        ProgressView()
                            .tint(row.paidInFull ? Color(hex: "#ecedee") : Color(hex: "#0e0f11"))
                    } else {
                        Text(row.paidInFull ? "Undo — mark open" : "Mark as paid")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(row.paidInFull ? Color(hex: "#8e9197") : Color(hex: "#0e0f11"))
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 11)
                        .fill(row.paidInFull ? Color(hex: "#1c1f23") : Color(hex: "#c8ff5a"))
                )
            }
            .buttonStyle(.plain)
            .disabled(anyBusy)
            .opacity(anyBusy && !busy ? 0.5 : 1)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(hex: "#15171a"))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(
                            row.paidInFull ? Color(hex: "#5ddf8a").opacity(0.35) : Color(hex: "#2a2d32"),
                            lineWidth: 1
                        )
                )
        )
    }

    private var maskedNumber: String {
        guard let four = row.lastFour, !four.isEmpty else { return "•••• ····" }
        return "•••• \(four)"
    }

    private var statusTag: some View {
        Text(row.paidInFull ? "PAID" : "OPEN")
            .font(.system(size: 10, weight: .bold))
            .tracking(1)
            .foregroundStyle(row.paidInFull ? Color(hex: "#5ddf8a") : Color(hex: "#ffb547"))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(
                    (row.paidInFull ? Color(hex: "#5ddf8a") : Color(hex: "#ffb547")).opacity(0.14)
                )
            )
    }

    private var utilizationColor: Color {
        switch row.utilizationStatus {
        case "over_limit": return Color(hex: "#ff6b6b")
        case "warning": return Color(hex: "#ffb547")
        case "ok": return Color(hex: "#5ddf8a")
        default: return Color(hex: "#8e9197")
        }
    }

    /// Mirrors the Panel's paymentDateForMonth: when the payment day is on or
    /// before the cutoff day, the payment for this statement month lands in the
    /// following calendar month.
    private var paymentDueDateLabel: String? {
        guard let dueDay = row.paymentDueDay else { return nil }
        let parts = month.split(separator: "-")
        guard parts.count == 2, let y = Int(parts[0]), let m = Int(parts[1]) else { return nil }
        let nextMonth = row.statementCutoffDay.map { dueDay <= $0 } ?? false
        var comps = DateComponents()
        comps.year = y
        comps.month = m + (nextMonth ? 1 : 0)
        comps.day = 1
        let calendar = Calendar.current
        guard let firstOfMonth = calendar.date(from: comps),
              let dayRange = calendar.range(of: .day, in: .month, for: firstOfMonth) else { return nil }
        comps.day = min(dueDay, dayRange.count)
        guard let date = calendar.date(from: comps) else { return nil }
        let f = DateFormatter(); f.dateFormat = "MMM d"
        return f.string(from: date)
    }

    private func miniStat(label: String, cents: Int?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color(hex: "#8e9197"))
                .tracking(0.5).textCase(.uppercase)
            if let cents {
                AmountLabel(cents: cents, font: .system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(hex: "#ecedee"))
            } else {
                Text("—")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(hex: "#5a5d63"))
            }
        }
    }

    private func moneyString(_ cents: Int) -> String {
        let value = Double(cents) / 100.0
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return "$" + (formatter.string(from: NSNumber(value: value)) ?? "\(value)")
    }
}

// MARK: - Empty / Error

private struct PaymentsEmptyView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "creditcard")
                .font(.system(size: 48))
                .foregroundStyle(Color(hex: "#5a5d63"))
            VStack(spacing: 8) {
                Text("No cards to pay")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color(hex: "#ecedee"))
                Text("Add credit cards in the Cards tab to track payments here")
                    .font(.system(size: 14))
                    .foregroundStyle(Color(hex: "#8e9197"))
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct FortnightEmptyView: View {
    let windowLabel: String
    let onShowAll: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 48))
                .foregroundStyle(Color(hex: "#5a5d63"))
            VStack(spacing: 8) {
                Text("No cards in this fortnight")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color(hex: "#ecedee"))
                Text("No card has a payment date in \(windowLabel.lowercased()). Cards without a cutoff or payment day are hidden.")
                    .font(.system(size: 14))
                    .foregroundStyle(Color(hex: "#8e9197"))
                    .multilineTextAlignment(.center)
            }
            Button(action: onShowAll) {
                Text("Show all cards")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(hex: "#0e0f11"))
                    .padding(.horizontal, 28).padding(.vertical, 12)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color(hex: "#c8ff5a")))
            }
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct PaymentsErrorView: View {
    let message: String
    let onRetry: () -> Void
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 32))
                .foregroundStyle(Color(hex: "#ffb547"))
            Text(message)
                .font(.system(size: 14))
                .foregroundStyle(Color(hex: "#8e9197"))
                .multilineTextAlignment(.center)
            Button("Retry", action: onRetry)
                .foregroundStyle(Color(hex: "#c8ff5a"))
                .font(.system(size: 15, weight: .semibold))
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

import SwiftUI
import Observation

// MARK: - ViewModel

@MainActor
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
    private var loadGeneration: UInt64 = 0
    private var recordPresentation = CardPaymentSaveLifecycle()

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
        _ = await refreshSummary(workspaceId: workspaceId, presentationToken: nil)
    }

    func beginRecordPresentation() -> UInt64 {
        recordPresentation.beginPresentation()
    }

    func invalidateRecordPresentation() {
        recordPresentation.invalidate()
        loadGeneration &+= 1
        busyCardId = nil
        isLoading = false
    }

    func ownsRecordPresentation(_ token: UInt64) -> Bool {
        recordPresentation.owns(token)
    }

    private func refreshSummary(
        workspaceId: String,
        presentationToken: UInt64?
    ) async -> CardPaymentRecordResult {
        guard presentationToken.map({ recordPresentation.owns($0) }) ?? true else { return .stale }
        loadGeneration &+= 1
        let generation = loadGeneration
        // Keep the existing rows visible while a refresh is in flight; roots
        // render the inline Signal trace alongside that retained content.
        isLoading = true
        errorMessage = nil
        defer {
            if generation == loadGeneration {
                isLoading = false
            }
        }
        do {
            let nextSummary: CardPaymentsSummaryResponse?
            let nextFortnightCards: [FortnightCard]?
            if let window = activeWindow {
                let prevMonth = CardPaymentFortnight.shiftMonth(window.monthKey, by: -1)
                async let currentResp: CardPaymentsSummaryResponse = api.fetch(
                    Endpoints.cardPaymentsSummary(workspaceId) + MonthRangeQuery.summaryQuery(month: window.monthKey)
                )
                async let previousResp: CardPaymentsSummaryResponse = api.fetch(
                    Endpoints.cardPaymentsSummary(workspaceId) + MonthRangeQuery.summaryQuery(month: prevMonth)
                )
                let (current, previous) = try await (currentResp, previousResp)
                nextFortnightCards = CardPaymentFortnight.mergeCards(
                    window: window,
                    currentMonthCards: current.creditCards,
                    previousMonthCards: previous.creditCards
                )
                nextSummary = nil
            } else {
                nextFortnightCards = nil
                nextSummary = try await api.fetch(
                    Endpoints.cardPaymentsSummary(workspaceId) + MonthRangeQuery.summaryQuery(month: month)
                )
            }
            guard presentationToken.map({ recordPresentation.owns($0) }) ?? true else { return .stale }
            guard generation == loadGeneration else {
                return presentationToken == nil
                    ? .stale
                    : .recordPaymentRefreshFailed("Payment status is still refreshing. Try again in a moment.")
            }
            fortnightCards = nextFortnightCards
            if let nextSummary {
                summary = nextSummary
            }
            return .refreshed
        } catch {
            guard presentationToken.map({ recordPresentation.owns($0) }) ?? true else { return .stale }
            guard generation == loadGeneration else {
                return presentationToken == nil
                    ? .stale
                    : .recordPaymentRefreshFailed("Payment status is still refreshing. Try again in a moment.")
            }
            errorMessage = error.localizedDescription
            return .recordPaymentRefreshFailed(error.localizedDescription)
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

    @MainActor
    func recordPayment(
        _ body: MonthlyCardPaymentBody,
        workspaceId: String,
        presentationToken: UInt64
    ) async throws -> CardPaymentRecordResult {
        guard ownsRecordPresentation(presentationToken) else { return .stale }
        busyCardId = body.creditCardId
        defer {
            if ownsRecordPresentation(presentationToken) {
                busyCardId = nil
            }
        }
        do {
            try await api.send(
                Endpoints.monthlyCardPayments(workspaceId),
                method: "POST",
                body: body
            )
        } catch {
            guard ownsRecordPresentation(presentationToken) else { return .stale }
            throw error
        }
        return await refreshSummary(workspaceId: workspaceId, presentationToken: presentationToken)
    }

    func refreshRecordedPayment(
        workspaceId: String,
        presentationToken: UInt64
    ) async -> CardPaymentRecordResult {
        await refreshSummary(workspaceId: workspaceId, presentationToken: presentationToken)
    }
}

// MARK: - View

struct CardPaymentsView: View {
    let workspaceId: String
    @State private var vm = CardPaymentsVM()

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()

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
        if vm.isLoading && vm.visibleCards.isEmpty {
            SettlrPulseLoadingView(message: "Loading payment status")
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
                if vm.errorMessage != nil {
                    SignalRefreshWarning(message: "Showing saved payment status. Refresh failed.") {
                        Task { await vm.load(workspaceId: workspaceId) }
                    }
                    .padding(.horizontal, 20)
                }

                if vm.isLoading {
                    SignalTraceLoadingView(lastUpdated: nil)
                        .padding(.horizontal, 20)
                }

                if let totals = vm.displayTotals {
                    TotalsStrip(totals: totals)
                        .padding(.horizontal, 20)
                }

                if let window = vm.activeWindow {
                    Text("Payment dates \(window.startDay)–\(window.endDay) · \(monthLabel(window.monthKey)). Cards without a cutoff or payment day are hidden.")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.faint)
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
                .foregroundStyle(selected == .all ? Theme.muted : Theme.accentText)
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .background(
                    Capsule()
                        .fill(Theme.surface)
                        .overlay(
                            Capsule().strokeBorder(
                                selected == .all ? Theme.line : Theme.accent.opacity(0.4),
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack {
            Button { change(by: -1) } label: {
                Image(systemName: "chevron.left")
                    .foregroundStyle(Theme.muted)
                    .frame(width: 44, height: 44)
            }
            Spacer()
            Button {
                let f = DateFormatter(); f.dateFormat = "yyyy-MM"
                selectedMonth = f.string(from: Date())
                onChanged()
            } label: {
                Text(displayLabel)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                    .frame(minHeight: 44)
                    .contentTransition(.numericText())
                    .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: selectedMonth)
            }
            .buttonStyle(.plain)
            Spacer()
            Button { change(by: 1) } label: {
                Image(systemName: "chevron.right")
                    .foregroundStyle(Theme.muted)
                    .frame(width: 44, height: 44)
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
            totalCell(label: "To pay", cents: totals.totalPaymentDueCents, color: Theme.expense)
            divider
            totalCell(label: "Recorded", cents: totals.totalPaymentsRecordedCents, color: Theme.ink)
            divider
            totalCell(label: "Still owed", cents: totals.remainingDueCents, color: Theme.warning)
        }
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Theme.surface)
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.line, lineWidth: 1))
        )
    }

    private var divider: some View {
        Rectangle()
            .fill(Theme.line)
            .frame(width: 1, height: 32)
    }

    private func totalCell(label: String, cents: Int, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.muted)
                .tracking(0.5).textCase(.uppercase)
            AmountLabel(cents: cents, font: .system(size: 14, weight: .semibold))
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Card tile

struct CardPaymentTile: View {
    let row: CardPaymentRow
    let month: String
    let busy: Bool
    let anyBusy: Bool
    let onSetPaid: (Bool) -> Void
    var onRecordPayment: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(row.label)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                    Text(maskedNumber)
                        .font(.caption.monospaced())
                        .foregroundStyle(Theme.faint)
                }
                Spacer()
                statusTag
            }

            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("To pay")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Theme.muted)
                        .tracking(0.5).textCase(.uppercase)
                    AmountLabel(cents: row.paymentDueCents, font: .title2.bold())
                        .foregroundStyle(Theme.ink)
                    if row.dueSource == "override" {
                        Text("Statement override · spend \(moneyString(row.spentCents))")
                            .font(.caption2)
                            .foregroundStyle(Theme.faint)
                    }
                }
                Spacer()
                if let due = paymentDueDateLabel {
                    VStack(alignment: .trailing, spacing: 3) {
                        Text("Due")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Theme.muted)
                            .tracking(0.5).textCase(.uppercase)
                        Text(due)
                            .font(.subheadline.weight(.semibold).monospaced())
                            .foregroundStyle(Theme.accentText)
                    }
                }
            }

            HStack(spacing: 16) {
                miniStat(label: "Recorded", cents: row.paymentsRecordedCents)
                miniStat(label: "Still owed", cents: row.paidInFull ? nil : row.outstandingCents)
                if let pct = row.utilizationPct {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Usage")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Theme.muted)
                            .tracking(0.5).textCase(.uppercase)
                        Text(String(format: pct.truncatingRemainder(dividingBy: 1) == 0 ? "%.0f%%" : "%.1f%%", pct))
                            .font(.caption.weight(.semibold).monospaced())
                            .foregroundStyle(utilizationColor)
                    }
                }
                Spacer()
            }

            paymentActions
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Theme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(
                            row.paidInFull ? Theme.income.opacity(0.35) : Theme.line,
                            lineWidth: 1
                        )
                )
        )
    }

    private var maskedNumber: String {
        guard let four = row.lastFour, !four.isEmpty else { return "•••• ····" }
        return "•••• \(four)"
    }

    @ViewBuilder
    private var paymentActions: some View {
        if let onRecordPayment, !row.paidInFull {
            Button(action: onRecordPayment) {
                Text("Record payment")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.buttonInk)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(RoundedRectangle(cornerRadius: 11).fill(Theme.accent))
            }
            .buttonStyle(.plain)
            .disabled(anyBusy)

            Button { onSetPaid(true) } label: {
                statusActionLabel("Mark as paid", busy: busy, ink: Theme.muted)
                    .background(RoundedRectangle(cornerRadius: 11).fill(Theme.surface2))
            }
            .buttonStyle(.plain)
            .disabled(anyBusy)
        } else {
            Button { onSetPaid(!row.paidInFull) } label: {
                statusActionLabel(
                    row.paidInFull ? "Undo paid status" : "Mark as paid",
                    busy: busy,
                    ink: row.paidInFull ? Theme.muted : Theme.buttonInk
                )
                .background(
                    RoundedRectangle(cornerRadius: 11)
                        .fill(row.paidInFull ? Theme.surface2 : Theme.accent)
                )
            }
            .buttonStyle(.plain)
            .disabled(anyBusy)
        }
    }

    @ViewBuilder
    private func statusActionLabel(_ title: String, busy: Bool, ink: Color) -> some View {
        Group {
            if busy {
                ProgressView().tint(ink)
            } else {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ink)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44)
    }

    private var statusTag: some View {
        Text(row.paidInFull ? "PAID" : "OPEN")
            .font(.caption2.bold())
            .tracking(1)
            .foregroundStyle(row.paidInFull ? Theme.income : Theme.warning)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(
                    (row.paidInFull ? Theme.income : Theme.warning).opacity(0.14)
                )
            )
    }

    private var utilizationColor: Color {
        switch row.utilizationStatus {
        case "over_limit": return Theme.expense
        case "warning": return Theme.warning
        case "ok": return Theme.income
        default: return Theme.muted
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
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Theme.muted)
                .tracking(0.5).textCase(.uppercase)
            if let cents {
                AmountLabel(cents: cents, font: .caption.weight(.semibold))
                    .foregroundStyle(Theme.ink)
            } else {
                Text("—")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.faint)
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

// MARK: - Record payment sheet

struct CardPaymentRecordSheet: View {
    let card: FortnightCard
    let onRecord: (MonthlyCardPaymentBody) async throws -> CardPaymentRecordResult
    let onRefresh: () async -> CardPaymentRecordResult
    let isPresentationCurrent: () -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var amountText: String
    @State private var paidAt = Date()
    @State private var note = ""
    @State private var errorMessage: String?
    @State private var isSaving = false
    @State private var recovery = CardPaymentRecordRecovery()
    @FocusState private var amountFocused: Bool
    @FocusState private var noteFocused: Bool

    init(
        card: FortnightCard,
        onRecord: @escaping (MonthlyCardPaymentBody) async throws -> CardPaymentRecordResult,
        onRefresh: @escaping () async -> CardPaymentRecordResult,
        isPresentationCurrent: @escaping () -> Bool
    ) {
        self.card = card
        self.onRecord = onRecord
        self.onRefresh = onRefresh
        self.isPresentationCurrent = isPresentationCurrent
        _amountText = State(initialValue: CardPaymentDraft.formattedAmount(cents: card.row.outstandingCents))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        cardContext

                        HeroAmountField(
                            amountText: $amountText,
                            tint: Theme.accentText,
                            focus: $amountFocused,
                            errorMessage: errorMessage
                        )

                        VStack(spacing: 0) {
                            SignalNativeFormRow {
                                DatePicker("Payment date", selection: $paidAt, displayedComponents: .date)
                                    .datePickerStyle(.compact)
                                    .tint(Theme.accent)
                                    .padding(.horizontal, 16)
                            }
                            SignalFormRow(label: "Note") {
                                TextField("Optional", text: $note)
                                    .focused($noteFocused)
                                    .autocorrectionDisabled()
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(Theme.ink)
                                    .multilineTextAlignment(.trailing)
                            }
                        }

                        Button(action: saveOrRefresh) {
                            Group {
                                if isSaving {
                                    ProgressView().tint(Theme.buttonInk)
                                } else {
                                    Text(recovery.nextAction == .refresh ? "Retry refresh" : "Record payment")
                                }
                            }
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(isSaving)
                        .accessibilityHint("Records this payment against the selected statement month")
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 40)
                    .disabled(isSaving)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("Record payment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Theme.muted)
                        .disabled(isSaving)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        amountFocused = false
                        noteFocused = false
                    }
                    .foregroundStyle(Theme.accentText)
                    .fontWeight(.semibold)
                    .disabled(isSaving)
                }
            }
        }
        .interactiveDismissDisabled(isSaving)
        .onAppear { amountFocused = true }
    }

    private var cardContext: some View {
        VStack(spacing: 4) {
            Text(card.row.label)
                .font(.headline)
                .foregroundStyle(Theme.ink)
            Text("Statement month · \(monthLabel(card.resolvedDueMonthKey))")
                .font(.subheadline)
                .foregroundStyle(Theme.muted)
            Text("Outstanding · \(moneyString(card.row.outstandingCents))")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.faint)
        }
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
        .accessibilityElement(children: .combine)
    }

    private func saveOrRefresh() {
        if recovery.nextAction == .refresh {
            refreshOnly()
        } else {
            recordPayment()
        }
    }

    private func recordPayment() {
        guard let body = CardPaymentDraft.makeBody(
            month: card.resolvedDueMonthKey,
            cardId: card.row.creditCardId,
            amountText: amountText,
            note: note,
            paidAt: paidAt
        ) else {
            errorMessage = "Enter an amount greater than zero."
            amountFocused = true
            return
        }

        isSaving = true
        errorMessage = nil
        Task {
            defer {
                if isPresentationCurrent() {
                    isSaving = false
                }
            }
            do {
                handle(await onRecord(body))
            } catch is CancellationError {
                // Workspace changes close the source sheet; do not attach an
                // error to a card that is no longer current.
            } catch {
                if isPresentationCurrent() {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func refreshOnly() {
        isSaving = true
        errorMessage = nil
        Task {
            defer {
                if isPresentationCurrent() {
                    isSaving = false
                }
            }
            handle(await onRefresh())
        }
    }

    private func handle(_ result: CardPaymentRecordResult) {
        guard !Task.isCancelled, isPresentationCurrent() else { return }
        switch recovery.receive(result, isPresentationCurrent: true) {
        case .dismiss:
            dismiss()
        case .showRefreshError(let message):
            errorMessage = "Payment was recorded, but status could not refresh. \(message)"
        case .ignore:
            break
        }
    }

    private func monthLabel(_ monthKey: String) -> String {
        let parts = monthKey.split(separator: "-")
        guard parts.count == 2, let year = Int(parts[0]), let month = Int(parts[1]) else { return monthKey }
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = 1
        guard let date = Calendar.current.date(from: components) else { return monthKey }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: date)
    }

    private func moneyString(_ cents: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "MXN"
        return formatter.string(from: NSNumber(value: Double(cents) / 100)) ?? "$\(cents / 100)"
    }
}

// MARK: - Empty / Error

private struct PaymentsEmptyView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "creditcard")
                .font(.system(size: 48))
                .foregroundStyle(Theme.faint)
            VStack(spacing: 8) {
                Text("No cards to pay")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Text("Add credit cards in the Cards tab to track payments here")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct FortnightEmptyView: View {
    let windowLabel: String
    let onShowAll: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 48))
                .foregroundStyle(Theme.faint)
            VStack(spacing: 8) {
                Text("No cards in this fortnight")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Text("No card has a payment date in \(windowLabel.lowercased()). Cards without a cutoff or payment day are hidden.")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
            }
            Button(action: onShowAll) {
                Text("Show all cards")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.buttonInk)
                    .padding(.horizontal, 28).padding(.vertical, 12)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Theme.accent))
                    .frame(minHeight: 44)
            }
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct PaymentsErrorView: View {
    let message: String
    let onRetry: () -> Void
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 32))
                .foregroundStyle(Theme.warning)
            Text(message)
                .font(.system(size: 14))
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
            Button("Retry", action: onRetry)
                .foregroundStyle(Theme.accentText)
                .font(.system(size: 15, weight: .semibold))
                .frame(minWidth: 44, minHeight: 44)
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

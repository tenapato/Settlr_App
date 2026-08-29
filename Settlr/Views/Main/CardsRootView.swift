import SwiftUI
import UIKit

/// The public Cards destination. Card management and payment tracking remain
/// separate endpoints, but share one quiet, feature-aware root.
struct CardsRootView: View {
    let workspaceId: String
    let canUsePayments: Bool

    @Environment(AppState.self) private var appState
    @State private var cardsVM = CardsVM()
    @State private var paymentVM: CardPaymentsVM?
    @State private var navigatorMode: FortnightNavigatorMode = .current
    @State private var showCardManagement = false
    @State private var selectedCard: CreditCard?

    private var referenceDate: Date { Date() }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if canUsePayments {
                        paymentSummary
                    }

                    cardsSection

                    if canUsePayments {
                        paymentStatuses
                    }

                    Spacer(minLength: 84)
                }
                .padding(.top, 8)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Cards")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        if canUsePayments {
                            Button("All cards") {
                                select(.all)
                            }

                            Divider()
                        }

                        Button {
                            showCardManagement = true
                        } label: {
                            Label("Manage cards", systemImage: "slider.horizontal.3")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("Card actions")
                }
            }
        }
        .task(id: workspaceId) { await load() }
        .onChange(of: canUsePayments) { _, enabled in
            guard enabled else {
                paymentVM = nil
                navigatorMode = .current
                return
            }
            Task { await loadPayments() }
        }
        .sheet(isPresented: $showCardManagement) {
            CardsView(workspaceId: workspaceId, vm: cardsVM) {
                await refreshAfterCardMutation()
            }
        }
        .sheet(item: $selectedCard) { card in
            CardDetailSheet(workspaceId: workspaceId, card: card) { body in
                guard isCurrentWorkspace else { throw CancellationError() }
                let updated = try await cardsVM.updateCard(workspaceId: workspaceId, cardId: card.id, body: body)
                guard isCurrentWorkspace else { return updated }
                await refreshAfterCardMutation()
                return updated
            }
        }
    }

    @ViewBuilder
    private var paymentSummary: some View {
        if let totals = paymentVM?.displayTotals {
            DueSummary(totals: totals)
                .padding(.horizontal, 20)
        } else if paymentVM?.isLoading == true {
            SignalTraceLoadingView(lastUpdated: nil)
                .padding(.horizontal, 20)
                .accessibilityLabel("Loading card payment summary")
        }
    }

    @ViewBuilder
    private var cardsSection: some View {
        if cardsVM.isLoading && cardsVM.cards.isEmpty {
            SettlrPulseLoadingView(message: "Loading cards")
                .frame(maxWidth: .infinity)
                .padding(.top, 28)
        } else if let error = cardsVM.errorMessage, cardsVM.cards.isEmpty {
            CardsErrorView(message: error) {
                Task { await cardsVM.load(workspaceId: workspaceId) }
            }
            .padding(.horizontal, 20)
        } else if cardsVM.cards.isEmpty {
            CardsEmptyView { showCardManagement = true }
                .padding(.horizontal, 20)
        } else {
            cardCarousel
            if let error = cardsVM.errorMessage {
                SignalRefreshWarning(message: "Showing saved card data. Refresh failed.") {
                    Task { await cardsVM.load(workspaceId: workspaceId) }
                }
                .padding(.horizontal, 20)
                .accessibilityValue(error)
            }
        }
    }

    private var cardCarousel: some View {
        VStack(alignment: .leading, spacing: 10) {
            TabView {
                ForEach(cardsVM.cards) { card in
                    VirtualCardFace(card: card, style: .hero)
                        .padding(.horizontal, 20)
                        .tag(card.id)
                        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .onTapGesture { selectedCard = card }
                        .accessibilityAddTraits(.isButton)
                        .accessibilityHint("Opens card details")
                }
            }
            .frame(height: 218)
            .tabViewStyle(.page(indexDisplayMode: cardsVM.cards.count > 1 ? .automatic : .never))
            .accessibilityLabel("Credit cards")

            if cardsVM.isLoading {
                SignalTraceLoadingView(lastUpdated: nil)
                    .padding(.horizontal, 20)
            }
        }
    }

    @ViewBuilder
    private var paymentStatuses: some View {
        if let paymentVM {
            VStack(alignment: .leading, spacing: 14) {
                FortnightNavigator(
                    referenceDate: referenceDate,
                    selection: $navigatorMode,
                    onSelect: select
                )
                .padding(.horizontal, 20)

                if paymentVM.isLoading && paymentVM.visibleCards.isEmpty {
                    SettlrPulseLoadingView(message: "Loading payment status")
                        .frame(maxWidth: .infinity)
                        .padding(.top, 12)
                } else if let error = paymentVM.errorMessage, paymentVM.visibleCards.isEmpty {
                    PaymentsErrorView(message: error) {
                        Task { await paymentVM.load(workspaceId: workspaceId) }
                    }
                    .padding(.horizontal, 20)
                } else if paymentVM.visibleCards.isEmpty {
                    FortnightEmptyView(windowLabel: paymentVM.activeWindow?.label ?? "this fortnight") {
                        select(.all)
                    }
                    .padding(.horizontal, 20)
                } else {
                    if paymentVM.isLoading {
                        SignalTraceLoadingView(lastUpdated: nil)
                            .padding(.horizontal, 20)
                    }
                    if let error = paymentVM.errorMessage {
                        SignalRefreshWarning(message: "Showing saved payment status. Refresh failed.") {
                            Task { await paymentVM.load(workspaceId: workspaceId) }
                        }
                        .padding(.horizontal, 20)
                        .accessibilityValue(error)
                    }
                    ForEach(paymentVM.visibleCards) { card in
                        CardPaymentTile(
                            row: card.row,
                            month: card.resolvedDueMonthKey,
                            busy: paymentVM.busyCardId == card.row.creditCardId,
                            anyBusy: paymentVM.busyCardId != nil
                        ) { paid in
                            Task {
                                await paymentVM.setPaid(
                                    paid,
                                    workspaceId: workspaceId,
                                    cardId: card.row.creditCardId
                                )
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                }
            }
        }
    }

    private func load() async {
        await cardsVM.load(workspaceId: workspaceId)
        guard canUsePayments else { return }
        await loadPayments()
    }

    private var isCurrentWorkspace: Bool {
        appState.activeWorkspace?.id == workspaceId
    }

    private func refreshAfterCardMutation() async {
        guard isCurrentWorkspace else { return }
        await cardsVM.load(workspaceId: workspaceId)
        guard isCurrentWorkspace, canUsePayments else { return }
        if paymentVM == nil {
            await loadPayments()
        } else if let paymentVM {
            paymentVM.fortnight = serverFilter(for: navigatorMode)
            await paymentVM.load(workspaceId: workspaceId)
        }
    }

    private func loadPayments() async {
        guard canUsePayments else { return }
        let payments = paymentVM ?? {
            let value = CardPaymentsVM()
            value.fortnight = serverFilter(for: navigatorMode)
            return value
        }()
        paymentVM = payments
        payments.fortnight = serverFilter(for: navigatorMode)
        await payments.load(workspaceId: workspaceId)
    }

    private func select(_ mode: FortnightNavigatorMode) {
        navigatorMode = mode
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        guard canUsePayments else { return }
        let payments = paymentVM ?? {
            let value = CardPaymentsVM()
            paymentVM = value
            return value
        }()
        payments.fortnight = serverFilter(for: mode)
        Task { await payments.load(workspaceId: workspaceId) }
    }

    private func serverFilter(for mode: FortnightNavigatorMode) -> FortnightFilter {
        switch mode {
        case .previous: return .last
        case .current: return .this
        case .next: return .next
        case .all: return .all
        }
    }
}

struct FortnightNavigator: View {
    let referenceDate: Date
    @Binding var selection: FortnightNavigatorMode
    let onSelect: (FortnightNavigatorMode) -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button {
                onSelect(previousMode)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Previous fortnight")

            Spacer(minLength: 0)

            VStack(spacing: 7) {
                Text(state.label)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.ink)
                    .contentTransition(.numericText())
                Capsule()
                    .fill(Theme.accent)
                    .frame(width: 34, height: 3)
            }
            .frame(minWidth: 120)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Selected card period")
            .accessibilityValue(state.label)

            Spacer(minLength: 0)

            Button {
                onSelect(nextMode)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Next fortnight")
        }
        .frame(maxWidth: .infinity)
        .animation(.snappy(duration: 0.2), value: selection)
    }

    private var state: FortnightNavigatorState {
        switch selection {
        case .previous: return .previous(reference: referenceDate)
        case .current: return .current(reference: referenceDate)
        case .next: return .next(reference: referenceDate)
        case .all: return .all(reference: referenceDate)
        }
    }

    private var previousMode: FortnightNavigatorMode {
        switch selection {
        case .previous: return .previous
        case .current, .all: return .previous
        case .next: return .current
        }
    }

    private var nextMode: FortnightNavigatorMode {
        switch selection {
        case .previous: return .current
        case .current, .all: return .next
        case .next: return .next
        }
    }
}

private struct DueSummary: View {
    let totals: CardPaymentsTotals

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("PAYMENT DUE")
                .font(.system(size: 11, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(Theme.accentText)
            AmountLabel(cents: totals.remainingDueCents, font: .system(size: 32, weight: .bold))
                .foregroundStyle(Theme.ink)
            Text(totals.remainingDueCents == 0 ? "Everything is paid" : "Still owed across your cards")
                .font(.system(size: 13))
                .foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Theme.surface)
                .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Theme.line, lineWidth: 1))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Card payments due")
    }
}

struct SignalRefreshWarning: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(Theme.warning)
            Text(message)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Retry", action: onRetry)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.accentText)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(message)
    }
}

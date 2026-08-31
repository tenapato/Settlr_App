import Foundation
import Observation

@MainActor
@Observable
final class ActivityVM {
    var timeline: [ActivityEvent] = []
    var attentionEvents: [BillSplitSummary] = []
    var expenses: [Expense] = []
    var incomes: [Income] = []
    var savings: [SavingsEntry] = []
    var savingsAccounts: [SavingsAccount] = []
    var splits: [BillSplitSummary] = []
    var categories: [Category] = []
    var cards: [CreditCard] = []
    var isLoading = false
    var hasLoaded = false
    var errorMessage: String?

    var selectedFilter: ActivityFilter = .all
    var selectedPeriod: ActivityPeriodFilter = .all
    var selectedCategoryID: String?
    var selectedPaymentSource: String?

    private let api = APIClient.shared
    private var loadGeneration = 0
    private var activeWorkspaceID: String?

    var hasActiveFilter: Bool {
        selectedFilter != .all
            || selectedPeriod != .all
            || selectedCategoryID != nil
            || selectedPaymentSource != nil
    }

    var activeFilterCount: Int {
        [selectedFilter != .all, selectedPeriod != .all, selectedCategoryID != nil, selectedPaymentSource != nil]
            .filter { $0 }
            .count
    }

    var filteredTimeline: [ActivityEvent] {
        timeline.filter { event in
            if let kind = selectedFilter.kind, event.kind != kind { return false }
            if !selectedPeriod.includes(event.occurredAt) { return false }
            if let category = selectedCategoryID, event.categoryID != category { return false }
            if let source = selectedPaymentSource {
                // The generic Card chip must continue to work when the cards
                // endpoint is unavailable: events retain their server card ID.
                if source == "credit_card" {
                    guard event.kind == .expense, event.paymentSource != nil, event.paymentSource != "cash" else { return false }
                } else if event.paymentSource != source {
                    return false
                }
            }
            return true
        }
    }

    func availableFilters(for user: MeUser?) -> [ActivityFilter] {
        var filters: [ActivityFilter] = [.all]
        if user?.has(.expenses) == true { filters.append(.expense) }
        if user?.has(.income) == true { filters.append(.income) }
        if user?.has(.savings) == true { filters.append(.savings) }
        if user?.has(.billSplits) == true { filters.append(.split) }
        return filters
    }

    func clearFilters() {
        selectedFilter = .all
        selectedPeriod = .all
        selectedCategoryID = nil
        selectedPaymentSource = nil
    }

    /// Immediately removes data and selections a feature revocation makes
    /// invalid. This runs before the replacement network load, so stale gated
    /// content cannot remain visible during the refresh window.
    func reconcileFeatures(for user: MeUser?) {
        let expensesEnabled = user?.has(.expenses) == true
        let incomeEnabled = user?.has(.income) == true
        let savingsEnabled = user?.has(.savings) == true
        let splitsEnabled = user?.has(.billSplits) == true
        let categoriesEnabled = user?.has(.categories) == true
        let cardsEnabled = user?.has(.creditCards) == true

        if !expensesEnabled { expenses = [] }
        if !incomeEnabled { incomes = [] }
        if !savingsEnabled { savings = []; savingsAccounts = [] }
        if !splitsEnabled { splits = [] }
        if !categoriesEnabled { categories = []; selectedCategoryID = nil }
        if !cardsEnabled {
            cards = []
        }
        if !cardsEnabled || !expensesEnabled { selectedPaymentSource = nil }
        let available = availableFilters(for: user)
        if !available.contains(selectedFilter) { selectedFilter = .all }

        let composed = ActivityComposer.compose(expenses: expenses, income: incomes, savings: savings, splits: splits)
        timeline = composed.timeline
        attentionEvents = composed.attention
    }

    func resetForWorkspace() {
        loadGeneration += 1
        activeWorkspaceID = nil
        timeline = []
        attentionEvents = []
        expenses = []
        incomes = []
        savings = []
        savingsAccounts = []
        splits = []
        categories = []
        cards = []
        isLoading = false
        hasLoaded = false
        errorMessage = nil
        clearFilters()
    }

    /// Fetches only routes the current feature set permits. Each resource is
    /// independent so a missing optional feature cannot blank cached content.
    func load(
        workspaceId: String,
        user: MeUser?,
        refreshSession: (() async -> Bool)? = nil
    ) async {
        let canLoadExpenses = user?.has(.expenses) == true
        let canLoadIncome = user?.has(.income) == true
        let canLoadSavings = user?.has(.savings) == true
        let canLoadSplits = user?.has(.billSplits) == true
        let canLoadCategories = user?.has(.categories) == true
        let canLoadCards = user?.has(.creditCards) == true && canLoadExpenses

        if activeWorkspaceID != workspaceId {
            resetForWorkspace()
            activeWorkspaceID = workspaceId
        }
        reconcileFeatures(for: user)
        loadGeneration += 1
        let generation = loadGeneration
        isLoading = true
        errorMessage = nil
        defer {
            if generation == loadGeneration, activeWorkspaceID == workspaceId {
                isLoading = false
                hasLoaded = true
            }
        }

        async let expenseResult = fetch(
            ExpensesResponse.self,
            endpoint: Endpoints.expenses(workspaceId),
            feature: .expenses,
            enabled: canLoadExpenses
        )
        async let incomeResult = fetch(
            IncomeListResponse.self,
            endpoint: Endpoints.income(workspaceId),
            feature: .income,
            enabled: canLoadIncome
        )
        async let savingsResult = fetch(
            SavingsEntriesResponse.self,
            endpoint: Endpoints.savingsEntries(workspaceId),
            feature: .savings,
            enabled: canLoadSavings
        )
        async let savingsAccountsResult = fetch(
            SavingsAccountsResponse.self,
            endpoint: Endpoints.savingsAccounts(workspaceId),
            feature: .savings,
            enabled: canLoadSavings
        )
        async let splitResult = fetch(
            BillSplitListResponse.self,
            endpoint: Endpoints.billSplits(workspaceId),
            feature: .billSplits,
            enabled: canLoadSplits
        )
        async let categoryResult = fetch(
            CategoriesResponse.self,
            endpoint: Endpoints.categories(workspaceId),
            feature: .categories,
            enabled: canLoadCategories && (canLoadExpenses || canLoadIncome)
        )
        async let cardResult = fetch(
            CreditCardsResponse.self,
            endpoint: Endpoints.creditCards(workspaceId),
            feature: .creditCards,
            enabled: canLoadCards
        )

        let results = await (expenseResult, incomeResult, savingsResult, savingsAccountsResult, splitResult, categoryResult, cardResult)
        guard generation == loadGeneration, activeWorkspaceID == workspaceId else { return }
        let failures = [
            results.0.failure,
            results.1.failure,
            results.2.failure,
            results.3.failure,
            results.4.failure,
            results.5.failure,
            results.6.failure
        ].compactMap { $0 }
        if let featureFailure = failures.first(where: { error in
            guard let server = error as? APIServerError else { return false }
            return server.status == 403 && server.feature != nil
        }) {
            let sessionRefreshSucceeded = await refreshSession?() ?? false
            guard generation == loadGeneration, activeWorkspaceID == workspaceId else { return }
            if !sessionRefreshSucceeded {
                errorMessage = featureFailure.localizedDescription
            }
            // The feature set may have changed while these concurrent requests
            // were in flight. Keep the already-reconciled cache and let the
            // refreshed session drive the next load; never apply the stale
            // gated result tuple after a feature-bearing refusal.
            return
        }

        if case .loaded(let response) = results.0 { expenses = response.expenses }
        if case .loaded(let response) = results.1 { incomes = response.income }
        if case .loaded(let response) = results.2 { savings = response.entries }
        if case .loaded(let response) = results.3 { savingsAccounts = response.accounts }
        if case .loaded(let response) = results.4 { splits = response.splits }
        if case .loaded(let response) = results.5 { categories = response.categories }
        if case .loaded(let response) = results.6 { cards = response.creditCards }

        if let first = failures.first { errorMessage = first.localizedDescription }
        let composed = ActivityComposer.compose(expenses: expenses, income: incomes, savings: savings, splits: splits)
        timeline = composed.timeline
        attentionEvents = composed.attention
        if let kind = selectedFilter.kind,
           !availableFilters(for: user).contains(where: { $0.kind == kind }) {
            selectedFilter = .all
        }
    }

    private enum ResourceResult<Value> {
        case skipped
        case loaded(Value)
        case failed(Error)

        var failure: Error? {
            if case .failed(let error) = self { return error }
            return nil
        }
    }

    private func fetch<Value: Decodable>(
        _ type: Value.Type,
        endpoint: String,
        feature: AppFeature,
        enabled: Bool
    ) async -> ResourceResult<Value> {
        guard enabled else { return .skipped }
        do {
            return .loaded(try await api.fetch(endpoint))
        } catch {
            return .failed(error)
        }
    }
}

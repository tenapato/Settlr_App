import Foundation
import Observation

@MainActor
@Observable
final class SavingsVM {
    var accounts: [SavingsAccount] = []
    var entries: [SavingsEntry] = []
    var recurring: [RecurringSavings] = []
    var totalBalanceCents: Int = 0
    var selectedAccountId: String? = nil // nil = All
    var isLoading = false
    var errorMessage: String?
    /// True once an accounts fetch has succeeded. An empty `accounts` only means
    /// "this workspace has none" when this is true — otherwise the load failed or
    /// hasn't finished, and callers must not treat it as a confirmed empty state.
    var hasLoadedAccounts = false

    /// Account responses are allowed to refresh independently from entries.
    /// Presenters use this marker to distinguish retained accounts from the
    /// current request's settled result (including a settled failure).
    private(set) var accountsRequestGeneration: Int = 0
    private(set) var settledAccountsRequestGeneration: Int?

    private let api = APIClient.shared
    private var inFlightLoad: Task<Void, Never>?
    private var loadGeneration = 0
    private var activeWorkspaceID: String?

    var displayBalanceCents: Int {
        if let id = selectedAccountId,
           let account = accounts.first(where: { $0.id == id }) {
            return account.balanceCents
        }
        return totalBalanceCents
    }

    var filteredEntries: [SavingsEntry] {
        guard let id = selectedAccountId else { return entries }
        return entries.filter { $0.accountId == id }
    }

    func account(for id: String) -> SavingsAccount? {
        accounts.first { $0.id == id }
    }

    /// True only when the accounts response belongs to the requested workspace.
    /// This keeps global quick actions from presenting a form with stale data.
    var loadedWorkspaceID: String? { activeWorkspaceID }

    var hasSettledCurrentAccountsRequest: Bool {
        guard activeWorkspaceID != nil else { return false }
        return settledAccountsRequestGeneration == loadGeneration
            && accountsRequestGeneration == loadGeneration
    }

    @MainActor
    func accountsRequestIsSettled(for workspaceId: String) -> Bool {
        activeWorkspaceID == workspaceId && hasSettledCurrentAccountsRequest
    }

    @MainActor
    func workspaceMutationGeneration(for workspaceId: String) -> Int {
        guard activeWorkspaceID == workspaceId else { return -1 }
        return loadGeneration
    }

    private func acceptsMutation(workspaceId: String, expectedGeneration: Int?) -> Bool {
        guard let expectedGeneration else { return true }
        return activeWorkspaceID == workspaceId && loadGeneration == expectedGeneration
    }

    var activeRecurringCount: Int {
        recurring.filter(\.active).count
    }

    @MainActor
    func load(workspaceId: String) async {
        if activeWorkspaceID != workspaceId {
            resetForWorkspace()
            activeWorkspaceID = workspaceId
        }
        loadGeneration += 1
        let generation = loadGeneration
        accountsRequestGeneration = generation
        settledAccountsRequestGeneration = nil
        isLoading = true
        errorMessage = nil
        let task = Task { @MainActor in await self.performLoad(workspaceId: workspaceId, generation: generation) }
        inFlightLoad = task
        await task.value
    }

    @MainActor
    func resetForWorkspace() {
        loadGeneration += 1
        activeWorkspaceID = nil
        inFlightLoad?.cancel()
        inFlightLoad = nil
        isLoading = false
        accounts = []
        entries = []
        recurring = []
        totalBalanceCents = 0
        selectedAccountId = nil
        hasLoadedAccounts = false
        accountsRequestGeneration = 0
        settledAccountsRequestGeneration = nil
        errorMessage = nil
    }

    /// Awaits the in-flight load, if any, so callers can act on settled state instead of
    /// racing it. Returns immediately when nothing is loading.
    @MainActor
    func awaitCurrentLoad() async {
        await inFlightLoad?.value
    }

    @MainActor
    private func performLoad(workspaceId: String, generation: Int) async {
        guard generation == loadGeneration, activeWorkspaceID == workspaceId else { return }
        defer {
            if generation == loadGeneration, activeWorkspaceID == workspaceId {
                isLoading = false
            }
        }

        // Recurring rules are supplementary: the endpoint may be absent on a given
        // deployment, and losing them must not blank out accounts and entries.
        async let recurringTask: RecurringSavingsListResponse? = try? await api.fetch(
            Endpoints.recurringSavings(workspaceId)
        )

        async let accountsTask: SavingsAccountsResponse = api.fetch(Endpoints.savingsAccounts(workspaceId))
        async let entriesTask: SavingsEntriesResponse = api.fetch(
            Endpoints.savingsEntries(workspaceId, accountId: selectedAccountId)
        )

        do {
            let accountsResp = try await accountsTask
            guard generation == loadGeneration, activeWorkspaceID == workspaceId else { return }
            accounts = accountsResp.accounts.sorted { $0.sortOrder < $1.sortOrder }
            totalBalanceCents = accountsResp.totalBalanceCents
            hasLoadedAccounts = true
            settledAccountsRequestGeneration = generation
            if let id = selectedAccountId, !accounts.contains(where: { $0.id == id }) {
                selectedAccountId = nil
            }
        } catch {
            guard generation == loadGeneration, activeWorkspaceID == workspaceId else { return }
            settledAccountsRequestGeneration = generation
            errorMessage = error.localizedDescription
        }

        do {
            let entriesResp = try await entriesTask
            guard generation == loadGeneration, activeWorkspaceID == workspaceId else { return }
            entries = entriesResp.entries
        } catch {
            guard generation == loadGeneration, activeWorkspaceID == workspaceId else { return }
            errorMessage = error.localizedDescription
        }

        guard generation == loadGeneration, activeWorkspaceID == workspaceId else { return }
        let recurringItems = await recurringTask?.recurringSavings ?? []
        guard generation == loadGeneration, activeWorkspaceID == workspaceId else { return }
        recurring = recurringItems
    }

    @MainActor
    func createAccount(
        workspaceId: String,
        name: String,
        color: String,
        targetAmountCents: Int? = nil,
        targetDate: String? = nil,
        expectedGeneration: Int? = nil
    ) async -> Bool {
        do {
            let resp: SavingsAccountResponse = try await api.fetch(
                Endpoints.savingsAccounts(workspaceId),
                method: "POST",
                body: CreateSavingsAccountBody(
                    name: name,
                    color: color,
                    currency: "MXN",
                    targetAmountCents: targetAmountCents,
                    targetDate: targetDate
                )
            )
            guard acceptsMutation(workspaceId: workspaceId, expectedGeneration: expectedGeneration) else { return false }
            accounts.append(resp.account)
            accounts.sort { $0.sortOrder < $1.sortOrder }
            return true
        } catch {
            guard acceptsMutation(workspaceId: workspaceId, expectedGeneration: expectedGeneration) else { return false }
            errorMessage = error.localizedDescription
            return false
        }
    }

    @MainActor
    func updateAccount(
        workspaceId: String,
        accountId: String,
        name: String,
        color: String,
        targetAmountCents: Int? = nil,
        targetDate: String? = nil,
        expectedGeneration: Int? = nil
    ) async -> Bool {
        do {
            let resp: SavingsAccountResponse = try await api.fetch(
                Endpoints.savingsAccount(workspaceId, accountId),
                method: "PATCH",
                body: UpdateSavingsAccountBody(
                    name: name,
                    color: color,
                    targetAmountCents: targetAmountCents,
                    targetDate: targetDate
                )
            )
            guard acceptsMutation(workspaceId: workspaceId, expectedGeneration: expectedGeneration) else { return false }
            if let idx = accounts.firstIndex(where: { $0.id == accountId }) {
                accounts[idx] = resp.account
            }
            return true
        } catch {
            guard acceptsMutation(workspaceId: workspaceId, expectedGeneration: expectedGeneration) else { return false }
            errorMessage = error.localizedDescription
            return false
        }
    }

    @MainActor
    func deleteAccount(
        workspaceId: String,
        accountId: String,
        expectedGeneration: Int? = nil
    ) async {
        do {
            try await api.send(Endpoints.savingsAccount(workspaceId, accountId), method: "DELETE")
            guard acceptsMutation(workspaceId: workspaceId, expectedGeneration: expectedGeneration) else { return }
            accounts.removeAll { $0.id == accountId }
            entries.removeAll { $0.accountId == accountId }
            if selectedAccountId == accountId { selectedAccountId = nil }
            totalBalanceCents = accounts.reduce(0) { $0 + $1.balanceCents }
        } catch {
            guard acceptsMutation(workspaceId: workspaceId, expectedGeneration: expectedGeneration) else { return }
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    func createEntry(
        workspaceId: String,
        body: CreateSavingsEntryBody,
        reload: Bool = true,
        expectedGeneration: Int? = nil
    ) async {
        do {
            let _: SavingsEntryResponse = try await api.fetch(
                Endpoints.savingsEntries(workspaceId),
                method: "POST",
                body: body
            )
            guard acceptsMutation(workspaceId: workspaceId, expectedGeneration: expectedGeneration) else { return }
            if reload { await load(workspaceId: workspaceId) }
        } catch {
            guard acceptsMutation(workspaceId: workspaceId, expectedGeneration: expectedGeneration) else { return }
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    func updateEntry(workspaceId: String, entryId: String, body: CreateSavingsEntryBody) async {
        do {
            let _: SavingsEntryResponse = try await api.fetch(
                Endpoints.savingsEntry(workspaceId, entryId),
                method: "PATCH",
                body: body
            )
            await load(workspaceId: workspaceId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    func deleteEntry(workspaceId: String, entryId: String) async {
        do {
            try await api.send(Endpoints.savingsEntry(workspaceId, entryId), method: "DELETE")
            await load(workspaceId: workspaceId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Recurring investments

    @MainActor
    func createRecurring(workspaceId: String, body: CreateRecurringSavingsBody) async -> Bool {
        do {
            let _: RecurringSavingsResponse = try await api.fetch(
                Endpoints.recurringSavings(workspaceId),
                method: "POST",
                body: body
            )
            await load(workspaceId: workspaceId)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    @MainActor
    func updateRecurring(
        workspaceId: String,
        ruleId: String,
        body: UpdateRecurringSavingsBody
    ) async -> Bool {
        do {
            let _: RecurringSavingsResponse = try await api.fetch(
                Endpoints.recurringSavingsRule(workspaceId, ruleId),
                method: "PATCH",
                body: body
            )
            await load(workspaceId: workspaceId)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    @MainActor
    func deleteRecurring(workspaceId: String, ruleId: String) async {
        do {
            try await api.send(
                Endpoints.recurringSavingsRule(workspaceId, ruleId),
                method: "DELETE"
            )
            await load(workspaceId: workspaceId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

import Foundation
import Observation

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

    private let api = APIClient.shared
    private var inFlightLoad: Task<Void, Never>?

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

    var activeRecurringCount: Int {
        recurring.filter(\.active).count
    }

    @MainActor
    func load(workspaceId: String) async {
        let task = Task { @MainActor in await self.performLoad(workspaceId: workspaceId) }
        inFlightLoad = task
        await task.value
    }

    /// Awaits the in-flight load, if any, so callers can act on settled state instead of
    /// racing it. Returns immediately when nothing is loading.
    @MainActor
    func awaitCurrentLoad() async {
        await inFlightLoad?.value
    }

    @MainActor
    private func performLoad(workspaceId: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        // Recurring rules are supplementary: the endpoint may be absent on a given
        // deployment, and losing them must not blank out accounts and entries.
        async let recurringTask: RecurringSavingsListResponse? = try? await api.fetch(
            Endpoints.recurringSavings(workspaceId)
        )

        do {
            async let accountsTask: SavingsAccountsResponse = api.fetch(Endpoints.savingsAccounts(workspaceId))
            async let entriesTask: SavingsEntriesResponse = api.fetch(
                Endpoints.savingsEntries(workspaceId, accountId: selectedAccountId)
            )
            let (accountsResp, entriesResp) = try await (accountsTask, entriesTask)
            accounts = accountsResp.accounts.sorted { $0.sortOrder < $1.sortOrder }
            totalBalanceCents = accountsResp.totalBalanceCents
            entries = entriesResp.entries
            hasLoadedAccounts = true
            if let id = selectedAccountId, !accounts.contains(where: { $0.id == id }) {
                selectedAccountId = nil
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        recurring = await recurringTask?.recurringSavings ?? []
    }

    @MainActor
    func createAccount(workspaceId: String, name: String, color: String) async -> Bool {
        do {
            let resp: SavingsAccountResponse = try await api.fetch(
                Endpoints.savingsAccounts(workspaceId),
                method: "POST",
                body: CreateSavingsAccountBody(name: name, color: color, currency: "MXN")
            )
            accounts.append(resp.account)
            accounts.sort { $0.sortOrder < $1.sortOrder }
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    @MainActor
    func updateAccount(workspaceId: String, accountId: String, name: String, color: String) async -> Bool {
        do {
            let resp: SavingsAccountResponse = try await api.fetch(
                Endpoints.savingsAccount(workspaceId, accountId),
                method: "PATCH",
                body: UpdateSavingsAccountBody(name: name, color: color)
            )
            if let idx = accounts.firstIndex(where: { $0.id == accountId }) {
                accounts[idx] = resp.account
            }
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    @MainActor
    func deleteAccount(workspaceId: String, accountId: String) async {
        do {
            try await api.send(Endpoints.savingsAccount(workspaceId, accountId), method: "DELETE")
            accounts.removeAll { $0.id == accountId }
            entries.removeAll { $0.accountId == accountId }
            if selectedAccountId == accountId { selectedAccountId = nil }
            totalBalanceCents = accounts.reduce(0) { $0 + $1.balanceCents }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    func createEntry(workspaceId: String, body: CreateSavingsEntryBody) async {
        do {
            let _: SavingsEntryResponse = try await api.fetch(
                Endpoints.savingsEntries(workspaceId),
                method: "POST",
                body: body
            )
            await load(workspaceId: workspaceId)
        } catch {
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

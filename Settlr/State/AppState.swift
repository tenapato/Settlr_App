import Foundation
import Observation

@Observable
final class AppState {
    var currentUser: MeUser?
    var activeWorkspace: WorkspaceWithRole?
    var isLoading = true
    var isRestoringWorkspace = false
    var signOutTrigger = false
    /// Share token from a `settlr://split/<token>` deep link, held until the app
    /// has finished loading and can present the claim screen over the UI.
    var pendingSplitShareToken: String?
    /// Set when the server reports this account was deactivated. Non-nil takes
    /// over the whole UI — see `ContentView`.
    var deactivation: DeactivationNotice?

    /// Why the app is locked. The reason is whatever note the admin left, and
    /// is often absent, so the screen has to read well without it.
    struct DeactivationNotice: Equatable {
        let reason: String?
    }

    var isAuthenticated: Bool { currentUser != nil }

    /// Extracts the share token from a Settlr deep link, or nil if it is some
    /// other `settlr://` URL (OAuth callbacks come back on the same scheme).
    static func splitShareToken(from url: URL) -> String? {
        guard url.scheme == "settlr", url.host == "split" else { return nil }
        let token = url.pathComponents.filter { $0 != "/" }.first
        guard let token, !token.isEmpty else { return nil }
        return token
    }

    private let api = APIClient.shared
    /// True once the server has confirmed the workspace this session is using.
    /// Until then `activeWorkspace` may be a cached guess, which is good enough
    /// to render the app but not to overwrite what the server says.
    private var hasVerifiedWorkspace = false

    @MainActor
    func initialize() async {
        defer { isLoading = false }

        // Installed before the first request, not after: a genuine 401 on this
        // very first `/api/me` used to bypass the handler entirely and be
        // handled by the catch below instead.
        api.onUnauthorized = { [weak self] in
            Task { @MainActor in self?.handleUnauthorized() }
        }
        api.onAccountDeactivated = { [weak self] reason in
            Task { @MainActor in self?.handleDeactivated(reason: reason) }
        }

        guard TokenStore.get() != nil else { return }

        // Render from the last known session immediately. A launch with no
        // signal has to reach `MainTabView` — that is where the "+" lives, and
        // a split someone is trying to save at a table is behind it.
        currentUser = OfflineSessionCache.user()
        activeWorkspace = OfflineSessionCache.workspace()

        do {
            let me: MeResponse = try await api.fetch(Endpoints.me)
            currentUser = me.user
            OfflineSessionCache.saveUser(me.user)
            await restoreLastWorkspaceIfNeeded()
        } catch APIError.unauthorized {
            // The only failure that actually means the session is over.
            handleUnauthorized()
        } catch {
            // Offline, a 5xx, a payload we couldn't decode — none of these say
            // the session is invalid. Signing the user out here would strand
            // them on a login screen that also needs the network, and would
            // orphan any splits waiting to upload under their account.
        }
    }

    @MainActor
    func restoreLastWorkspaceIfNeeded() async {
        guard !hasVerifiedWorkspace, currentUser != nil else { return }
        guard let savedId = LastWorkspaceStore.get() else { return }
        isRestoringWorkspace = true
        defer { isRestoringWorkspace = false }
        do {
            let response: WorkspacesResponse = try await api.fetch(Endpoints.workspaces)
            var workspaces = response.workspaces
            if workspaces.isEmpty {
                let bootstrap: CreateWorkspaceResponse = try await api.fetch(
                    Endpoints.bootstrapWorkspace,
                    method: "POST"
                )
                workspaces = [bootstrap.asWorkspaceWithRole]
            }
            hasVerifiedWorkspace = true
            if let match = workspaces.first(where: { $0.id == savedId }) {
                activeWorkspace = match
                OfflineSessionCache.saveWorkspace(match)
            } else {
                // Confirmed gone — only now is it safe to forget it.
                activeWorkspace = nil
                LastWorkspaceStore.delete()
                OfflineSessionCache.clear()
            }
        } catch {
            // Unverified, so keep whatever the cache seeded. Clearing here would
            // send an offline user to the workspace picker, which can't load.
        }
    }

    /// Re-reads the session so an admin's change to this user's features or
    /// status takes effect without waiting for a cold launch. Silent on
    /// failure — a refresh that couldn't reach the server says nothing about
    /// whether the session is still good.
    @MainActor
    func refreshSession() async {
        guard TokenStore.get() != nil, currentUser != nil else { return }
        guard let me: MeResponse = try? await api.fetch(Endpoints.me) else { return }
        currentUser = me.user
        OfflineSessionCache.saveUser(me.user)
    }

    @MainActor
    private func handleUnauthorized() {
        currentUser = nil
        activeWorkspace = nil
        hasVerifiedWorkspace = false
        TokenStore.delete()
        LastWorkspaceStore.delete()
        OfflineSessionCache.clear()
    }

    /// Deliberately keeps the token. It buys no access — the server refuses
    /// every route for a deactivated account — but it is what lets a relaunch
    /// arrive back at this same screen instead of a login form that will only
    /// reject them again.
    @MainActor
    private func handleDeactivated(reason: String?) {
        // The sign-out request itself is refused with the same 401, and its
        // handler lands after the fact. Without this guard that late callback
        // puts the lock screen back up over the login form the user just reached.
        guard TokenStore.get() != nil else { return }
        deactivation = DeactivationNotice(reason: reason)
    }

    @MainActor
    func signOut() async {
        try? await api.send(Endpoints.signOut, method: "POST")
        // Drops the token first, which is what makes the guard above effective;
        // no suspension point separates the two, so nothing can interleave.
        handleUnauthorized()
        deactivation = nil
    }

    @MainActor
    func deleteAccount() async throws {
        let userId = currentUser?.id
        try await api.deleteAccount()
        // Unlike signing out, there is no account left for these to upload to.
        if let userId { PendingSplitQueue.shared.removeAll(userId: userId) }
        handleUnauthorized()
    }

    @MainActor
    func select(_ workspace: WorkspaceWithRole) {
        activeWorkspace = workspace
        // Chosen from a list the server just returned, so this is confirmed.
        hasVerifiedWorkspace = true
        LastWorkspaceStore.save(workspace.id)
        OfflineSessionCache.saveWorkspace(workspace)
    }
}

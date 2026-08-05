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

    func initialize() async {
        defer { isLoading = false }
        guard TokenStore.get() != nil else { return }
        do {
            let me: MeResponse = try await api.fetch(Endpoints.me)
            currentUser = me.user
            await restoreLastWorkspaceIfNeeded()
        } catch {
            TokenStore.delete()
            LastWorkspaceStore.delete()
        }
        api.onUnauthorized = { [weak self] in
            Task { @MainActor in
                self?.currentUser = nil
                self?.activeWorkspace = nil
                TokenStore.delete()
                LastWorkspaceStore.delete()
            }
        }
    }

    @MainActor
    func restoreLastWorkspaceIfNeeded() async {
        guard activeWorkspace == nil, currentUser != nil else { return }
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
            if let match = workspaces.first(where: { $0.id == savedId }) {
                activeWorkspace = match
            } else {
                LastWorkspaceStore.delete()
            }
        } catch {
            // Keep picker visible if restore fails.
        }
    }

    @MainActor
    func signOut() async {
        try? await api.send(Endpoints.signOut, method: "POST")
        TokenStore.delete()
        LastWorkspaceStore.delete()
        currentUser = nil
        activeWorkspace = nil
    }

    @MainActor
    func deleteAccount() async throws {
        try await api.deleteAccount()
        TokenStore.delete()
        LastWorkspaceStore.delete()
        currentUser = nil
        activeWorkspace = nil
    }

    @MainActor
    func select(_ workspace: WorkspaceWithRole) {
        activeWorkspace = workspace
        LastWorkspaceStore.save(workspace.id)
    }
}

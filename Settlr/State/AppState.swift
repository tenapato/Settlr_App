import Foundation
import Observation

@Observable
final class AppState {
    var currentUser: MeUser?
    var activeWorkspace: WorkspaceWithRole?
    var isLoading = true
    var signOutTrigger = false

    var isAuthenticated: Bool { currentUser != nil }

    private let api = APIClient.shared

    func initialize() async {
        defer { isLoading = false }
        guard TokenStore.get() != nil else { return }
        do {
            let me: MeResponse = try await api.fetch(Endpoints.me)
            currentUser = me.user
        } catch {
            TokenStore.delete()
        }
        api.onUnauthorized = { [weak self] in
            Task { @MainActor in
                self?.currentUser = nil
                self?.activeWorkspace = nil
                TokenStore.delete()
            }
        }
    }

    @MainActor
    func signOut() async {
        try? await api.send(Endpoints.signOut, method: "POST")
        TokenStore.delete()
        currentUser = nil
        activeWorkspace = nil
    }

    @MainActor
    func select(_ workspace: WorkspaceWithRole) {
        activeWorkspace = workspace
    }
}

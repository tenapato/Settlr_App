import Foundation
import Observation

@Observable
final class WorkspacePickerVM {
    var workspaces: [WorkspaceWithRole] = []
    var isLoading = false
    var isCreating = false
    var newWorkspaceName = ""
    var errorMessage: String?
    var showCreateSheet = false

    private let api = APIClient.shared

    @MainActor
    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let response: WorkspacesResponse = try await api.fetch(Endpoints.workspaces)
            workspaces = response.workspaces
            // First-time user: auto-create personal workspace
            if workspaces.isEmpty {
                let bootstrap: CreateWorkspaceResponse = try await api.fetch(
                    Endpoints.bootstrapWorkspace,
                    method: "POST"
                )
                workspaces = [bootstrap.asWorkspaceWithRole]
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    func createWorkspace() async -> WorkspaceWithRole? {
        guard !newWorkspaceName.trimmingCharacters(in: .whitespaces).isEmpty else {
            errorMessage = "Workspace name cannot be empty."
            return nil
        }
        isCreating = true
        defer { isCreating = false }
        do {
            let response: CreateWorkspaceResponse = try await api.fetch(
                Endpoints.workspaces,
                method: "POST",
                body: CreateWorkspaceBody(name: newWorkspaceName)
            )
            newWorkspaceName = ""
            showCreateSheet = false
            return response.asWorkspaceWithRole
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }
}

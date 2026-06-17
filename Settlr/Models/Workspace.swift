import Foundation

struct Workspace: Codable, Identifiable {
    let id: String
    let name: String
    let kind: String
}

struct WorkspaceWithRole: Codable, Identifiable {
    let id: String
    let name: String
    let kind: String
    let role: String
}

struct WorkspacesResponse: Decodable {
    let workspaces: [WorkspaceWithRole]
}

struct CreateWorkspaceBody: Encodable {
    let name: String
}

// POST /api/workspaces returns { workspace: {...}, role: "owner" }
struct CreateWorkspaceResponse: Decodable {
    let workspace: WorkspaceBase
    let role: String

    var asWorkspaceWithRole: WorkspaceWithRole {
        WorkspaceWithRole(id: workspace.id, name: workspace.name, kind: workspace.kind, role: role)
    }
}

struct WorkspaceBase: Decodable {
    let id: String
    let name: String
    let kind: String
}

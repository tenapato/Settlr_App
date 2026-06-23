import Foundation

enum LastWorkspaceStore {
    private static let key = "last_workspace_id"

    static func save(_ workspaceId: String) {
        UserDefaults.standard.set(workspaceId, forKey: key)
    }

    static func get() -> String? {
        UserDefaults.standard.string(forKey: key)
    }

    static func delete() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}

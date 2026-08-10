import Foundation

/// The least we need on disk to render the app before the network answers.
///
/// Every screen fetches on appear, so without this a launch with no signal has
/// nothing to draw and — worse — `AppState.initialize()` used to read the failed
/// `/api/me` as a dead session and delete the token, dropping the user onto a
/// login screen that also needs the network. Splits composed offline would be
/// unreachable for the same reason: the "+" button lives inside `MainTabView`,
/// which an unresolved workspace never reaches.
///
/// This is identity and chrome only — who is signed in, which workspace, and
/// the cards a new expense can be charged to. Ledger data is deliberately not
/// cached: a stale balance shown as current is worse than a spinner. Receipt
/// drafts live in `PendingSplitQueue`'s protected file, not here.
enum OfflineSessionCache {
    private static let userKey = "cached_me_user"
    private static let workspaceKey = "cached_active_workspace"
    private static func cardsKey(_ workspaceId: String) -> String {
        "cached_credit_cards.\(workspaceId)"
    }

    static func saveUser(_ user: MeUser) { write(user, key: userKey) }
    static func user() -> MeUser? { read(MeUser.self, key: userKey) }

    static func saveWorkspace(_ workspace: WorkspaceWithRole) { write(workspace, key: workspaceKey) }
    static func workspace() -> WorkspaceWithRole? { read(WorkspaceWithRole.self, key: workspaceKey) }

    /// Cards are cached per workspace because a split charged to the wrong card
    /// is a wrong ledger row, not a cosmetic slip. Without them the create sheet
    /// silently forces every offline split to "cash".
    static func saveCreditCards(_ cards: [CreditCard], workspaceId: String) {
        write(cards, key: cardsKey(workspaceId))
    }

    static func creditCards(workspaceId: String) -> [CreditCard] {
        read([CreditCard].self, key: cardsKey(workspaceId)) ?? []
    }

    /// Called when the session is genuinely over — a 401 or an explicit sign-out
    /// — never when the network merely failed.
    static func clear() {
        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys
        where key == userKey || key == workspaceKey || key.hasPrefix("cached_credit_cards.") {
            defaults.removeObject(forKey: key)
        }
    }

    private static func write(_ value: some Encodable, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    private static func read<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}

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

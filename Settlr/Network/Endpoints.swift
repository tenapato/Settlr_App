import Foundation

enum Endpoints {
    static let me = "/api/me"
    static let workspaces = "/api/workspaces"
    static let bootstrapWorkspace = "/api/me/workspaces/bootstrap"
    static let signIn = "/api/auth/sign-in/email"
    static let signUp = "/api/auth/sign-up/email"
    static let signOut = "/api/auth/sign-out"

    static func workspace(_ id: String) -> String { "/api/workspaces/\(id)" }
    static func expenses(_ wsId: String) -> String { "/api/workspaces/\(wsId)/expenses" }
    static func expense(_ wsId: String, _ id: String) -> String { "/api/workspaces/\(wsId)/expenses/\(id)" }
    static func income(_ wsId: String) -> String { "/api/workspaces/\(wsId)/income" }
    static func incomeItem(_ wsId: String, _ id: String) -> String { "/api/workspaces/\(wsId)/income/\(id)" }
    static func categories(_ wsId: String) -> String { "/api/workspaces/\(wsId)/categories" }
    static func category(_ wsId: String, _ id: String) -> String { "/api/workspaces/\(wsId)/categories/\(id)" }
    static func summary(_ wsId: String) -> String { "/api/workspaces/\(wsId)/summary" }

    static func creditCards(_ wsId: String) -> String { "/api/workspaces/\(wsId)/credit-cards" }
    static func creditCard(_ wsId: String, _ id: String) -> String { "/api/workspaces/\(wsId)/credit-cards/\(id)" }
}

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
    static func recurringIncome(_ wsId: String) -> String { "/api/workspaces/\(wsId)/recurring-income" }
    static func recurringIncomeRule(_ wsId: String, _ id: String) -> String { "/api/workspaces/\(wsId)/recurring-income/\(id)" }
    static func categories(_ wsId: String) -> String { "/api/workspaces/\(wsId)/categories" }
    static func category(_ wsId: String, _ id: String) -> String { "/api/workspaces/\(wsId)/categories/\(id)" }
    static func summary(_ wsId: String) -> String { "/api/workspaces/\(wsId)/summary" }
    static func annualSummary(_ wsId: String) -> String { "/api/workspaces/\(wsId)/annual-summary" }

    static func telegramStatus(_ wsId: String) -> String { "/api/workspaces/\(wsId)/telegram/status" }
    static func telegramDisconnect(_ wsId: String) -> String { "/api/workspaces/\(wsId)/telegram/disconnect" }

    static func creditCards(_ wsId: String) -> String { "/api/workspaces/\(wsId)/credit-cards" }
    static func creditCard(_ wsId: String, _ id: String) -> String { "/api/workspaces/\(wsId)/credit-cards/\(id)" }
    static func cardPaymentsSummary(_ wsId: String) -> String { "/api/workspaces/\(wsId)/card-payments/summary" }
    static func markCardPaid(_ wsId: String, _ cardId: String) -> String { "/api/workspaces/\(wsId)/card-payments/cards/\(cardId)/mark-paid" }
    static func unmarkCardPaid(_ wsId: String, _ cardId: String) -> String { "/api/workspaces/\(wsId)/card-payments/cards/\(cardId)/unmark-paid" }

    static func savingsAccounts(_ wsId: String) -> String { "/api/workspaces/\(wsId)/savings/accounts" }
    static func savingsAccount(_ wsId: String, _ id: String) -> String { "/api/workspaces/\(wsId)/savings/accounts/\(id)" }
    static func savingsEntries(_ wsId: String, accountId: String? = nil) -> String {
        var path = "/api/workspaces/\(wsId)/savings/entries"
        if let accountId {
            path += "?accountId=\(accountId)"
        }
        return path
    }
    static func savingsEntry(_ wsId: String, _ id: String) -> String { "/api/workspaces/\(wsId)/savings/entries/\(id)" }
    static func recurringSavings(_ wsId: String) -> String { "/api/workspaces/\(wsId)/savings/recurring" }
    static func recurringSavingsRule(_ wsId: String, _ id: String) -> String { "/api/workspaces/\(wsId)/savings/recurring/\(id)" }

    // Bill splits — organizer side
    static func billSplits(_ wsId: String) -> String { "/api/workspaces/\(wsId)/bill-splits" }
    static func billSplit(_ wsId: String, _ id: String) -> String { "/api/workspaces/\(wsId)/bill-splits/\(id)" }
    static func billSplitItems(_ wsId: String, _ id: String) -> String { "/api/workspaces/\(wsId)/bill-splits/\(id)/items" }
    static func billSplitClaims(_ wsId: String, _ id: String) -> String { "/api/workspaces/\(wsId)/bill-splits/\(id)/claims" }
    static func billSplitParticipant(_ wsId: String, _ id: String, _ participantId: String) -> String {
        "/api/workspaces/\(wsId)/bill-splits/\(id)/participants/\(participantId)"
    }
    static func billSplitSettle(_ wsId: String, _ id: String, _ participantId: String) -> String {
        "/api/workspaces/\(wsId)/bill-splits/\(id)/participants/\(participantId)/settle"
    }
    static func billSplitScanReceipt(_ wsId: String) -> String { "/api/workspaces/\(wsId)/bill-splits/scan-receipt" }

    // Bill splits — public share link (no session; see APIClient.publicSplit*)
    static func publicSplit(_ shareToken: String) -> String { "/api/split/\(shareToken)" }
    static func publicSplitJoin(_ shareToken: String) -> String { "/api/split/\(shareToken)/join" }
    static func publicSplitClaims(_ shareToken: String) -> String { "/api/split/\(shareToken)/claims" }
}

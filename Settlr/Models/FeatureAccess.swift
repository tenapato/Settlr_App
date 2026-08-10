import Foundation

/// The per-user feature toggles an admin controls from the panel. Raw values are
/// the server's own identifiers — they arrive verbatim in `MeUser.disabledFeatures`
/// and appear in the `feature` field of a 403, so they must not drift.
///
/// `statements` and `assistant` are listed for completeness: the server gates
/// routes on them, but the iOS app has no screen for either yet.
enum AppFeature: String, CaseIterable {
    case expenses
    case income
    case savings
    case categories
    case creditCards = "credit_cards"
    case cardPayments = "card_payments"
    case statements
    case assistant
    case billSplits = "bill_splits"
}

extension MeUser {
    func has(_ feature: AppFeature) -> Bool { hasFeature(feature.rawValue) }
}

// MARK: - Navigation availability
//
// Every "is this reachable" decision lives here rather than at the call sites.
// A tab, its segmented picker and the switch that renders the segment are three
// separate pieces of code that have to agree; when the rule lived in each of
// them, disabling a feature left a picker entry that rendered an empty screen.

extension Tab {
    /// Tabs this user can reach, in bar order. Home is unconditional — the
    /// dashboard reads the summary endpoint, which is not feature-gated, and a
    /// tab bar has to have somewhere to land.
    static func available(for user: MeUser?) -> [Tab] {
        allCases.filter { $0.isAvailable(for: user) }
    }

    func isAvailable(for user: MeUser?) -> Bool {
        switch self {
        case .home:
            return true
        case .activity:
            return !ActivitySegment.available(for: user).isEmpty
        case .cards:
            return !CardsCategoriesSegment.available(for: user).isEmpty
        case .payments:
            // The card-payment routes carry `requireFeature` for both, so a user
            // with only one of them would reach a screen that 403s on load.
            return (user?.has(.cardPayments) ?? false) && (user?.has(.creditCards) ?? false)
        }
    }
}

extension ActivitySegment {
    static func available(for user: MeUser?) -> [ActivitySegment] {
        allCases.filter { $0.isAvailable(for: user) }
    }

    func isAvailable(for user: MeUser?) -> Bool {
        switch self {
        case .expenses: return user?.has(.expenses) ?? false
        case .income: return user?.has(.income) ?? false
        case .savings: return user?.has(.savings) ?? false
        }
    }
}

extension CardsCategoriesSegment {
    static func available(for user: MeUser?) -> [CardsCategoriesSegment] {
        allCases.filter { $0.isAvailable(for: user) }
    }

    func isAvailable(for user: MeUser?) -> Bool {
        switch self {
        case .cards: return user?.has(.creditCards) ?? false
        case .categories: return user?.has(.categories) ?? false
        }
    }
}

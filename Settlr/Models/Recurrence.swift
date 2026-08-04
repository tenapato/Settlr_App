import Foundation

/// How often a recurring rule repeats. Shared by recurring income and investments.
enum RecurrenceFrequency: String, CaseIterable, Codable, Hashable {
    case daily
    case weekly
    case biweekly
    case monthly

    var label: String {
        switch self {
        case .daily: return "Every day"
        case .weekly: return "Every week"
        case .biweekly: return "Every 2 weeks"
        case .monthly: return "Every month"
        }
    }

    var shortLabel: String {
        switch self {
        case .daily: return "Daily"
        case .weekly: return "Weekly"
        case .biweekly: return "Biweekly"
        case .monthly: return "Monthly"
        }
    }
}

typealias SavingsFrequency = RecurrenceFrequency

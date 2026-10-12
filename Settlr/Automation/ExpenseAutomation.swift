import AppIntents
import Foundation
import Observation

struct AutomationExpenseDraft: Identifiable, Equatable {
    let id = UUID()
    let amount: Double?
    let merchant: String
    let card: String
    let name: String
    let isWalletPayment: Bool
    let createdAt = Date()

    init(amount: Double? = nil, merchant: String = "", card: String = "", name: String = "", isWalletPayment: Bool = false) {
        // Missing or unusable Wallet values stay empty for the user to correct.
        self.amount = amount.flatMap { $0.isFinite && $0 > 0 && $0 < Double(Int.max / 100) ? $0 : nil }
        self.merchant = merchant.trimmingCharacters(in: .whitespacesAndNewlines)
        self.card = card.trimmingCharacters(in: .whitespacesAndNewlines)
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.isWalletPayment = isWalletPayment
    }

    var description: String { merchant.isEmpty ? name : merchant }
    var amountText: String {
        guard let amount else { return "" }
        return String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), amount)
    }
}

/// Match only a unique card. Network names and ambiguous labels need review.
enum WalletCardMatcher {
    static func match(_ walletLabel: String, cards: [CreditCard]) -> String? {
        let active = cards.filter { !$0.isArchived }
        let normalized = normalize(walletLabel)
        guard !normalized.isEmpty else { return nil }
        let digitGroups = walletLabel.components(separatedBy: CharacterSet.decimalDigits.inverted)
        let lastFour = digitGroups.last { $0.count == 4 }
        if let lastFour {
            let matches = active.filter { $0.lastFour == lastFour }
            if matches.count == 1 { return matches[0].id }
        }
        let matches = active.filter { normalize($0.label) == normalized }
        return matches.count == 1 ? matches[0].id : nil
    }

    private static func normalize(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .filter { $0.isLetter || $0.isNumber }
    }
}

enum AutomationSplitPayment {
    static func matches(amountCents: Int, currency: String, split: BillSplit) -> Bool {
        guard amountCents > 0, split.currency == currency else { return false }
        switch split.payerMode {
        case .organizerPaid: return amountCents == split.totalCents
        case .eachOwn: return !split.isOpen && amountCents == split.organizer?.owedCents
        case .unavailable: return false
        }
    }
}

/// App intents run in the foreground app process. Keep requests until login and
/// workspace selection finish, and never replace a draft the user is editing.
@MainActor
@Observable
final class ExpenseAutomationInbox {
    static let shared = ExpenseAutomationInbox()
    private(set) var drafts: [AutomationExpenseDraft] = []

    func removeAll() { drafts.removeAll() }
    func enqueue(_ draft: AutomationExpenseDraft) { drafts.append(draft) }
    func remove(id: UUID) { drafts.removeAll { $0.id == id } }
}

struct WalletExpenseIntent: AppIntent {
    static var title: LocalizedStringResource = "Wallet Payment → Settlr"
    static var description = IntentDescription("Open an expense draft using the Amount and Merchant from a Wallet automation. Review it in Settlr before saving.")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Amount") var amount: Double?
    @Parameter(title: "Merchant") var merchant: String?
    @Parameter(title: "Card or Pass") var card: String?
    @Parameter(title: "Name") var name: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Review Wallet payment of \(\.$amount) at \(\.$merchant)") {
            \.$card
            \.$name
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        ExpenseAutomationInbox.shared.enqueue(AutomationExpenseDraft(
            amount: amount, merchant: merchant ?? "", card: card ?? "", name: name ?? "", isWalletPayment: true
        ))
        return .result()
    }
}

struct QuickExpenseIntent: AppIntent {
    static var title: LocalizedStringResource = "Quick Expense"
    static var description = IntentDescription("Open a blank expense draft in Settlr. Use this with Back Tap or the Action button.")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        ExpenseAutomationInbox.shared.enqueue(AutomationExpenseDraft())
        return .result()
    }
}

struct SettlrShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: WalletExpenseIntent(),
            phrases: ["Review a Wallet payment in \(.applicationName)"],
            shortTitle: "Wallet Payment", systemImageName: "creditcard"
        )
        AppShortcut(
            intent: QuickExpenseIntent(),
            phrases: ["Log an expense in \(.applicationName)"],
            shortTitle: "Quick Expense", systemImageName: "plus.circle"
        )
    }
}

extension Notification.Name {
    static let expenseAutomationSaved = Notification.Name("expenseAutomationSaved")
}

import Foundation

enum ActivityEventKind: String, CaseIterable, Identifiable {
    case expense
    case income
    case savings
    case split

    var id: String { rawValue }

    var title: String {
        switch self {
        case .expense: return "Expenses"
        case .income: return "Income"
        case .savings: return "Savings"
        case .split: return "Splits"
        }
    }

    var symbol: String {
        switch self {
        case .expense: return "arrow.up"
        case .income: return "arrow.down"
        case .savings: return "banknote"
        case .split: return "person.2"
        }
    }
}

/// The small, display-ready value used by Activity. Keeping this model free of
/// SwiftUI means the ordering and de-duplication rules can be tested without an
/// app target or network client.
struct ActivityEvent: Identifiable, Equatable {
    let id: String
    let occurredAt: Date
    let kind: ActivityEventKind
    let title: String
    let context: String
    let amountCents: Int
    let destinationID: String
    let categoryID: String?
    let paymentSource: String?
    let marker: String?

    init(
        id: String,
        occurredAt: Date,
        kind: ActivityEventKind,
        title: String,
        context: String,
        amountCents: Int,
        destinationID: String,
        categoryID: String? = nil,
        paymentSource: String? = nil,
        marker: String? = nil
    ) {
        self.id = id
        self.occurredAt = occurredAt
        self.kind = kind
        self.title = title
        self.context = context
        self.amountCents = amountCents
        self.destinationID = destinationID
        self.categoryID = categoryID
        self.paymentSource = paymentSource
        self.marker = marker
    }
}

enum ActivityFilter: String, CaseIterable, Identifiable {
    case all
    case expense
    case income
    case savings
    case split

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .expense: return "Expenses"
        case .income: return "Income"
        case .savings: return "Savings"
        case .split: return "Splits"
        }
    }

    var kind: ActivityEventKind? {
        switch self {
        case .all: return nil
        case .expense: return .expense
        case .income: return .income
        case .savings: return .savings
        case .split: return .split
        }
    }
}

enum ActivityPeriodFilter: String, CaseIterable, Identifiable {
    case all
    case today
    case week
    case month

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "Any time"
        case .today: return "Today"
        case .week: return "This week"
        case .month: return "This month"
        }
    }

    func includes(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        switch self {
        case .all: return true
        case .today:
            return calendar.isDate(date, inSameDayAs: now)
        case .week:
            guard let start = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: now)) else {
                return false
            }
            return date >= start && date <= now
        case .month:
            return calendar.component(.month, from: date) == calendar.component(.month, from: now)
                && calendar.component(.year, from: date) == calendar.component(.year, from: now)
        }
    }
}

enum ActivityComposer {
    static func compose(
        expenses: [Expense],
        income: [Income],
        savings: [SavingsEntry],
        splits: [BillSplitSummary]
    ) -> (timeline: [ActivityEvent], attention: [BillSplitSummary]) {
        let splitByID = Dictionary(uniqueKeysWithValues: splits.map { ($0.id, $0) })
        let attention = splits
            .filter { $0.status == "open" }
            .sorted { parseDate($0.occurredAt) > parseDate($1.occurredAt) }

        var events: [ActivityEvent] = []
        events.reserveCapacity(expenses.count + income.count + savings.count + splits.count)

        for expense in expenses {
            // An open split is still a pending attention item, not a completed
            // ledger event. Completed splits are represented by their owned
            // expense and carry a Split marker.
            if let splitID = expense.billSplitId, splitByID[splitID]?.status == "open" {
                continue
            }
            let isSplit = expense.billSplitId.flatMap { splitByID[$0] } != nil
            let payment = expense.paymentChannel == "credit_card" ? "Card" : "Cash"
            let context = isSplit ? "(payment) · Split" : payment
            events.append(
                ActivityEvent(
                    id: "expense:\(expense.id)",
                    occurredAt: parseDate(expense.occurredAt),
                    kind: .expense,
                    title: expense.description,
                    context: context,
                    amountCents: -abs(expense.amountCents),
                    destinationID: expense.id,
                    categoryID: expense.categoryId,
                    paymentSource: expense.creditCardId ?? expense.paymentChannel,
                    marker: isSplit ? "Split" : nil
                )
            )
        }

        for item in income {
            let context = item.source?.isEmpty == false ? item.source! : "Income"
            events.append(
                ActivityEvent(
                    id: "income:\(item.id)",
                    occurredAt: parseDate(item.occurredAt),
                    kind: .income,
                    title: item.description,
                    context: context,
                    amountCents: abs(item.amountCents),
                    destinationID: item.id,
                    categoryID: item.categoryId,
                    paymentSource: item.source,
                    marker: item.isRecurring ? "Recurring" : nil
                )
            )
        }

        for item in savings {
            let isDeposit = item.isDeposit
            events.append(
                ActivityEvent(
                    id: "savings:\(item.id)",
                    occurredAt: parseDate(item.occurredAt),
                    kind: .savings,
                    title: item.description,
                    context: isDeposit ? "Deposit · Savings" : "Withdrawal · Savings",
                    amountCents: isDeposit ? -abs(item.amountCents) : abs(item.amountCents),
                    destinationID: item.accountId,
                    paymentSource: item.accountId,
                    marker: "Savings"
                )
            )
        }

        let expenseSplitIDs = Set(expenses.compactMap { expense -> String? in
            guard let splitID = expense.billSplitId, splitByID[splitID]?.status != "open" else { return nil }
            return splitID
        })
        // A split with no owned expense still needs a completed timeline entry;
        // when its expense exists, emitting this row would duplicate the bill.
        for split in splits where split.status != "open" && !expenseSplitIDs.contains(split.id) {
            events.append(
                ActivityEvent(
                    id: "split:\(split.id)",
                    occurredAt: parseDate(split.occurredAt),
                    kind: .split,
                    title: split.merchant,
                    context: "Split · \(split.status.capitalized)",
                    amountCents: -abs(split.totalCents),
                    destinationID: split.id,
                    marker: "Split"
                )
            )
        }

        return (
            timeline: events.sorted {
                if $0.occurredAt != $1.occurredAt { return $0.occurredAt > $1.occurredAt }
                return $0.id < $1.id
            },
            attention: attention
        )
    }

    private static func parseDate(_ raw: String) -> Date {
        if let seconds = Double(raw), seconds > 1_000_000_000 {
            return Date(timeIntervalSince1970: seconds > 1_000_000_000_000 ? seconds / 1000 : seconds)
        }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: raw) { return date }
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: raw) { return date }
        for format in ["yyyy-MM-dd'T'HH:mm:ssZ", "yyyy-MM-dd"] {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = format
            if let date = formatter.date(from: raw) { return date }
        }
        return .distantPast
    }
}

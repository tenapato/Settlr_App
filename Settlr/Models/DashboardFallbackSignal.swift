import Foundation

struct DashboardFallbackSignal: Identifiable, Equatable {
    enum Kind: Equatable {
        case income
        case spending
        case available
        case savings
        case noSpending
        case movementCount
        case noMovement
    }

    let id: String
    let kind: Kind
    let signedCents: Int?
    let count: Int?
}

struct DashboardFallbackSignalSet: Equatable {
    let signals: [DashboardFallbackSignal]
    let isQuiet: Bool

    var shouldAnimate: Bool { !isQuiet && signals.count > 1 }
}

enum DashboardSignalSectionMode: Equatable {
    case spending(primaryIndex: Int, tickerIndices: [Int])
    case fallback(animated: Bool)

    static func resolve(
        realInsightCount: Int,
        fallback: DashboardFallbackSignalSet
    ) -> DashboardSignalSectionMode {
        let visibleInsightCount = min(max(realInsightCount, 0), 5)
        if visibleInsightCount > 0 {
            return .spending(
                primaryIndex: 0,
                tickerIndices: Array(1..<visibleInsightCount)
            )
        }
        return .fallback(animated: fallback.shouldAnimate)
    }
}

enum DashboardFallbackSignals {
    static func build(summary: SummaryResponse) -> DashboardFallbackSignalSet {
        let hasMovement = summary.incomeCents != 0
            || summary.expenseCents != 0
            || summary.availableCents != 0
            || summary.savingsNetCents != 0
            || summary.transactionCount != 0

        guard hasMovement else {
            return DashboardFallbackSignalSet(
                signals: [
                    DashboardFallbackSignal(
                        id: "no-movement",
                        kind: .noMovement,
                        signedCents: nil,
                        count: nil
                    ),
                ],
                isQuiet: true
            )
        }

        var signals: [DashboardFallbackSignal] = []

        if summary.incomeCents != 0 {
            signals.append(moneySignal(id: "income", kind: .income, signedCents: summary.incomeCents))
        }
        if summary.expenseCents != 0 {
            signals.append(moneySignal(id: "spending", kind: .spending, signedCents: -summary.expenseCents))
        }

        signals.append(moneySignal(id: "available", kind: .available, signedCents: summary.availableCents))

        if summary.savingsNetCents != 0 {
            signals.append(moneySignal(id: "savings", kind: .savings, signedCents: -summary.savingsNetCents))
        }
        if summary.expenseCents == 0 {
            signals.append(
                DashboardFallbackSignal(
                    id: "no-spending",
                    kind: .noSpending,
                    signedCents: nil,
                    count: nil
                )
            )
        }
        if summary.transactionCount > 0 {
            signals.append(
                DashboardFallbackSignal(
                    id: "movement-count",
                    kind: .movementCount,
                    signedCents: nil,
                    count: summary.transactionCount
                )
            )
        }

        return DashboardFallbackSignalSet(signals: Array(signals.prefix(5)), isQuiet: false)
    }

    private static func moneySignal(
        id: String,
        kind: DashboardFallbackSignal.Kind,
        signedCents: Int
    ) -> DashboardFallbackSignal {
        DashboardFallbackSignal(id: id, kind: kind, signedCents: signedCents, count: nil)
    }
}

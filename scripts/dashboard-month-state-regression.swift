import Foundation

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fatalError(message)
    }
}

@main
struct DashboardMonthStateRegression {
    static func main() {
        let cachedFailureMonth = DashboardMonthState.selectedMonthAfterFailedLoad(
            requestedMonth: "2026-02",
            selectedMonth: "2026-02",
            lastSuccessfulMonth: "2026-01",
            hasCachedSummary: true,
            requestGeneration: 2,
            currentGeneration: 2
        )
        require(cachedFailureMonth == "2026-01", "cached snapshot failure must restore the last successful month")

        let firstLoadFailureMonth = DashboardMonthState.selectedMonthAfterFailedLoad(
            requestedMonth: "2026-02",
            selectedMonth: "2026-02",
            lastSuccessfulMonth: nil,
            hasCachedSummary: false,
            requestGeneration: 1,
            currentGeneration: 1
        )
        require(firstLoadFailureMonth == "2026-02", "first-load failure must retain the requested month")

        let supersededFailureMonth = DashboardMonthState.selectedMonthAfterFailedLoad(
            requestedMonth: "2026-02",
            selectedMonth: "2026-03",
            lastSuccessfulMonth: "2026-01",
            hasCachedSummary: true,
            requestGeneration: 2,
            currentGeneration: 3
        )
        require(supersededFailureMonth == "2026-03", "superseded failure must not roll back a newer selection")

        print("Dashboard month state regression passed.")
    }
}

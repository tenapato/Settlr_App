import Foundation

enum DashboardMonthState {
    static func selectedMonthAfterFailedLoad(
        requestedMonth: String,
        selectedMonth: String,
        lastSuccessfulMonth: String?,
        hasCachedSummary: Bool,
        requestGeneration: Int,
        currentGeneration: Int
    ) -> String {
        guard requestGeneration == currentGeneration,
              selectedMonth == requestedMonth,
              hasCachedSummary,
              let lastSuccessfulMonth else {
            return selectedMonth
        }
        return lastSuccessfulMonth
    }
}

import Foundation
import Observation

@MainActor
@Observable
final class DashboardVM {
    var summary: SummaryResponse?
    var previousSummary: SummaryResponse?
    var isLoading = false
    var errorMessage: String?
    /// Date of the last successful current-month summary response.
    var lastUpdated: Date?
    var selectedMonth: String = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM"
        return f.string(from: Date())
    }()

    private let api = APIClient.shared
    private var loadGeneration = 0
    private var lastSuccessfulMonth: String?
    private var suppressedMonthReload: String?

    func consumeMonthChangeReloadSuppression(for month: String) -> Bool {
        guard suppressedMonthReload == month else {
            suppressedMonthReload = nil
            return false
        }
        suppressedMonthReload = nil
        return true
    }

    @MainActor
    func load(workspaceId: String) async {
        loadGeneration += 1
        let generation = loadGeneration
        isLoading = true
        defer {
            if generation == loadGeneration { isLoading = false }
        }

        let month = selectedMonth
        let currentPath = Endpoints.summary(workspaceId) + MonthRangeQuery.summaryQuery(month: month)

        async let currentTask: SummaryResponse = api.fetch(currentPath)
        async let previousTask: SummaryResponse? = {
            guard let prevMonth = MonthRangeQuery.previousMonth(month) else { return nil }
            let previousPath = Endpoints.summary(workspaceId) + MonthRangeQuery.summaryQuery(month: prevMonth)
            return try? await api.fetch(previousPath)
        }()

        do {
            let freshSummary = try await currentTask
            let freshPreviousSummary = await previousTask
            guard generation == loadGeneration, selectedMonth == month else { return }
            // Commit the two comparison periods as one snapshot. A failed or
            // superseded month request must not pair retained current data with
            // a previous-month response from a different selection.
            summary = freshSummary
            previousSummary = freshPreviousSummary
            lastSuccessfulMonth = month
            lastUpdated = Date()
            errorMessage = nil
        } catch {
            _ = await previousTask
            guard generation == loadGeneration, selectedMonth == month else { return }
            // Keep the last valid summary visible while a refresh fails. The
            // view presents the error inline so a transient network failure
            // cannot erase the user's financial context.
            let restoredMonth = DashboardMonthState.selectedMonthAfterFailedLoad(
                requestedMonth: month,
                selectedMonth: selectedMonth,
                lastSuccessfulMonth: lastSuccessfulMonth,
                hasCachedSummary: summary != nil,
                requestGeneration: generation,
                currentGeneration: loadGeneration
            )
            if restoredMonth != selectedMonth {
                suppressedMonthReload = restoredMonth
                selectedMonth = restoredMonth
            }
            errorMessage = error.localizedDescription
        }
    }
}

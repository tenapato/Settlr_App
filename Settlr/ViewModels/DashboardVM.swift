import Foundation
import Observation

@Observable
final class DashboardVM {
    var summary: SummaryResponse?
    var previousSummary: SummaryResponse?
    var isLoading = false
    var errorMessage: String?
    var selectedMonth: String = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM"
        return f.string(from: Date())
    }()

    private let api = APIClient.shared

    @MainActor
    func load(workspaceId: String) async {
        isLoading = true
        defer { isLoading = false }

        let month = selectedMonth
        let currentPath = Endpoints.summary(workspaceId) + MonthRangeQuery.summaryQuery(month: month)

        async let currentTask: SummaryResponse = api.fetch(currentPath)
        async let previousTask: SummaryResponse? = {
            guard let prevMonth = MonthRangeQuery.previousMonth(month) else { return nil }
            let previousPath = Endpoints.summary(workspaceId) + MonthRangeQuery.summaryQuery(month: prevMonth)
            return try? await api.fetch(previousPath)
        }()

        do {
            summary = try await currentTask
            errorMessage = nil
        } catch {
            summary = nil
            errorMessage = error.localizedDescription
        }
        previousSummary = await previousTask
    }
}

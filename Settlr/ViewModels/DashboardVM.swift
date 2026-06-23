import Foundation
import Observation

@Observable
final class DashboardVM {
    var summary: SummaryResponse?
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
        do {
            let path = Endpoints.summary(workspaceId) + MonthRangeQuery.summaryQuery(month: selectedMonth)
            summary = try await api.fetch(path)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

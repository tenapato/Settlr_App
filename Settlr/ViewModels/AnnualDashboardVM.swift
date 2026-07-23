import Foundation
import Observation

@Observable
@MainActor
final class AnnualDashboardVM {
    var months: [MonthDataPoint] = []
    var isLoading = false
    private var loadedYear: Int?
    private let api = APIClient.shared

    func load(workspaceId: String, year: Int) async {
        guard year != loadedYear else { return }
        isLoading = true
        defer { isLoading = false }
        let path = Endpoints.annualSummary(workspaceId) + "?year=\(year)"
        if let result: AnnualSummaryResponse = try? await api.fetch(path) {
            months = result.months
            loadedYear = year
        }
    }

    func invalidate() {
        loadedYear = nil
    }
}

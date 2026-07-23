import Foundation
import Observation

@Observable
final class TelegramSettingsVM {
    var status: TelegramStatusResponse?
    var isLoading = false
    var isDisconnecting = false
    var errorMessage: String?

    private let api = APIClient.shared

    var isConnected: Bool { status?.connected == true }

    @MainActor
    func load(workspaceId: String) async {
        isLoading = status == nil
        defer { isLoading = false }
        errorMessage = nil
        do {
            status = try await api.fetch(Endpoints.telegramStatus(workspaceId))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    func disconnect(workspaceId: String) async {
        isDisconnecting = true
        errorMessage = nil
        defer { isDisconnecting = false }
        do {
            try await api.send(Endpoints.telegramDisconnect(workspaceId), method: "DELETE")
            status = TelegramStatusResponse(connected: false, telegramUsername: nil, connectedAt: nil)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

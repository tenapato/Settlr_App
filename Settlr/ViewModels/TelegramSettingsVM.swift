import Foundation
import Observation
import UIKit

@Observable
final class TelegramSettingsVM {
    var status: TelegramStatusResponse?
    var isLoading = false
    var isConnecting = false
    var isDisconnecting = false
    var errorMessage: String?
    var connectUrl: String?
    var pendingConnect = false

    private let api = APIClient.shared

    var isConnected: Bool { status?.connected == true }

    @MainActor
    func load(workspaceId: String) async {
        isLoading = status == nil
        defer { isLoading = false }
        errorMessage = nil
        do {
            let response: TelegramStatusResponse = try await api.fetch(
                Endpoints.telegramStatus(workspaceId)
            )
            status = response
            if response.connected {
                pendingConnect = false
                connectUrl = nil
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    func connect(workspaceId: String) async {
        isConnecting = true
        errorMessage = nil
        defer { isConnecting = false }
        do {
            let response: TelegramGenerateLinkResponse = try await api.fetch(
                Endpoints.telegramGenerateLink(workspaceId),
                method: "POST"
            )
            connectUrl = response.url
            pendingConnect = true
            if let url = URL(string: response.url) {
                await UIApplication.shared.open(url)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    func openConnectUrl() async {
        guard let connectUrl, let url = URL(string: connectUrl) else { return }
        await UIApplication.shared.open(url)
    }

    @MainActor
    func disconnect(workspaceId: String) async {
        isDisconnecting = true
        errorMessage = nil
        defer { isDisconnecting = false }
        do {
            try await api.send(Endpoints.telegramDisconnect(workspaceId), method: "DELETE")
            status = TelegramStatusResponse(connected: false, telegramUsername: nil, connectedAt: nil)
            pendingConnect = false
            connectUrl = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    func pollWhilePending(workspaceId: String) async {
        while !Task.isCancelled && pendingConnect && !isConnected {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled, pendingConnect else { return }
            await load(workspaceId: workspaceId)
        }
    }
}

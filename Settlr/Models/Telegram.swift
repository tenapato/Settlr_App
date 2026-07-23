import Foundation

struct TelegramStatusResponse: Decodable {
    let connected: Bool
    let telegramUsername: String?
    let connectedAt: String?
}

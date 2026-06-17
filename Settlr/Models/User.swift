import Foundation

struct MeUser: Codable, Identifiable {
    let id: String
    let name: String
    let email: String
    let emailVerified: Bool
    let role: String?
}

struct MeResponse: Decodable {
    let user: MeUser
}

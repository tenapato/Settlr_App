import Foundation

struct MeUser: Codable, Identifiable {
    let id: String
    let name: String
    let email: String
    let emailVerified: Bool
    let role: String?
    /// Features an admin turned off for this user. Absent on older payloads.
    let disabledFeatures: [String]?

    /// Admins bypass feature gating server-side, so mirror that here rather than
    /// hiding UI they are allowed to reach.
    func hasFeature(_ feature: String) -> Bool {
        if role == "admin" { return true }
        return !(disabledFeatures ?? []).contains(feature)
    }
}

struct MeResponse: Decodable {
    let user: MeUser
}

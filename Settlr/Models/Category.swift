import Foundation

struct Category: Codable, Identifiable {
    let id: String
    let name: String
    let scope: String
    let color: String?
    let parentId: String?
}

struct CategoriesResponse: Decodable {
    let categories: [Category]
}

import Foundation

struct Artist: Identifiable, Codable, Hashable {
    let itemId: String
    let provider: String
    let name: String
    let sortName: String?
    let uri: String
    let imageUrl: String?
    var favorite: Bool?

    var id: String { itemId }

    enum CodingKeys: String, CodingKey {
        case itemId = "item_id"
        case provider
        case name
        case sortName = "sort_name"
        case uri
        case imageUrl = "image"
    }
}

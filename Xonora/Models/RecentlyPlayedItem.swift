import Foundation

/// Represents a recently played item from Music Assistant
/// The API returns an ItemMapping which contains media_type and item details
struct RecentlyPlayedItem: Identifiable, Codable, Hashable {
    let itemId: String
    let provider: String
    let name: String
    let mediaType: String
    let uri: String
    let imageUrl: String?

    // Optional nested item details (for tracks, albums, etc.)
    let artist: String?
    let album: String?
    let duration: TimeInterval?

    var id: String { "\(mediaType)_\(itemId)_\(provider)" }

    enum CodingKeys: String, CodingKey {
        case itemId = "item_id"
        case provider
        case name
        case mediaType = "media_type"
        case uri
        case imageUrl = "image"
        case artist
        case album
        case duration
    }

    // Custom decoder to handle flexible API responses
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        itemId = try container.decode(String.self, forKey: .itemId)
        provider = try container.decode(String.self, forKey: .provider)
        name = try container.decode(String.self, forKey: .name)
        mediaType = try container.decode(String.self, forKey: .mediaType)
        uri = try container.decode(String.self, forKey: .uri)

        // Image can be nested or at root level
        if let img = try? container.decode(String.self, forKey: .imageUrl) {
            imageUrl = img
        } else if let imgDict = try? container.decode([String: String].self, forKey: .imageUrl),
                  let url = imgDict["url"] ?? imgDict["path"] {
            imageUrl = url
        } else {
            imageUrl = nil
        }

        // Optional fields - try different keys for artist
        if let artistStr = try? container.decode(String.self, forKey: .artist) {
            artist = artistStr
        } else if let artistDict = try? container.decode([String: Any].self, forKey: .artist) as? [String: String],
                  let artistName = artistDict["name"] {
            artist = artistName
        } else {
            artist = nil
        }

        album = try? container.decodeIfPresent(String.self, forKey: .album)
        duration = try? container.decodeIfPresent(TimeInterval.self, forKey: .duration)
    }

    // Regular initializer for testing/preview
    init(itemId: String, provider: String, name: String, mediaType: String, uri: String, imageUrl: String?, artist: String?, album: String?, duration: TimeInterval?) {
        self.itemId = itemId
        self.provider = provider
        self.name = name
        self.mediaType = mediaType
        self.uri = uri
        self.imageUrl = imageUrl
        self.artist = artist
        self.album = album
        self.duration = duration
    }
}

// Helper extension to decode Any type
extension KeyedDecodingContainer {
    func decode(_ type: [String: Any].Type, forKey key: K) throws -> [String: Any] {
        let container = try self.nestedContainer(keyedBy: JSONCodingKeys.self, forKey: key)
        return try container.decode(type)
    }
}

private struct JSONCodingKeys: CodingKey {
    var stringValue: String
    var intValue: Int?

    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) {
        self.stringValue = "\(intValue)"
        self.intValue = intValue
    }
}

extension KeyedDecodingContainer where K == JSONCodingKeys {
    func decode(_ type: [String: Any].Type) throws -> [String: Any] {
        var dict = [String: Any]()
        for key in allKeys {
            if let value = try? decode(String.self, forKey: key) {
                dict[key.stringValue] = value
            } else if let value = try? decode(Int.self, forKey: key) {
                dict[key.stringValue] = value
            } else if let value = try? decode(Double.self, forKey: key) {
                dict[key.stringValue] = value
            } else if let value = try? decode(Bool.self, forKey: key) {
                dict[key.stringValue] = value
            }
        }
        return dict
    }
}

import Foundation

struct ProjectDTO: Decodable, Identifiable, Hashable, Sendable {
    let id: UUID
    var name: String
    var description: String?
    var status: String
    var area: String?
    var tags: [String]
    var createdAt: Date
    var updatedAt: Date
}

struct ProjectCreateRequest: Encodable, Sendable {
    var name: String
    var description: String?
    var status: String = "active"
    var area: String?
    var tags: [String] = []
}

struct ProjectUpdateRequest: Encodable, Sendable {
    var name: String?
    var description: String?
    var status: String?
    var area: String?
    var tags: [String]?

    enum CodingKeys: String, CodingKey {
        case name
        case description
        case status
        case area
        case tags
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encodeIfPresent(status, forKey: .status)
        try container.encodeIfPresent(area, forKey: .area)
        try container.encodeIfPresent(tags, forKey: .tags)
    }
}

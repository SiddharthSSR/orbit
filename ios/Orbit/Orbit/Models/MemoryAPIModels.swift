import Foundation

struct MemoryDTO: Decodable, Identifiable, Hashable, Sendable {
    let id: UUID
    var title: String
    var body: String
    var kind: String
    var sourceUrl: String?
    var projectId: UUID? = nil
    var tags: [String]
    var isArchived: Bool
    var createdAt: Date
    var updatedAt: Date
}

struct MemoryCreateRequest: Encodable, Sendable {
    var title: String
    var body: String
    var kind: String = "note"
    var sourceUrl: String?
    var projectId: UUID? = nil
    var tags: [String] = []
    var isArchived: Bool = false
}

/// Focused PATCH body for assigning or removing a memory's project.
/// Unlike `encodeIfPresent`, encoding the Optional directly preserves an
/// explicit JSON null so the backend can distinguish unlink from omission.
struct MemoryProjectLinkRequest: Encodable, Sendable {
    var projectId: UUID?

    enum CodingKeys: String, CodingKey {
        case projectId
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(projectId, forKey: .projectId)
    }
}

struct MemoryUpdateRequest: Encodable, Sendable {
    var title: String?
    var body: String?
    var kind: String?
    var sourceUrl: String?
    var tags: [String]?
    var isArchived: Bool?

    enum CodingKeys: String, CodingKey {
        case title
        case body
        case kind
        case sourceUrl
        case tags
        case isArchived
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(title, forKey: .title)
        try container.encodeIfPresent(body, forKey: .body)
        try container.encodeIfPresent(kind, forKey: .kind)
        try container.encodeIfPresent(sourceUrl, forKey: .sourceUrl)
        try container.encodeIfPresent(tags, forKey: .tags)
        try container.encodeIfPresent(isArchived, forKey: .isArchived)
    }
}

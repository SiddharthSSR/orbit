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

/// Lightweight, read-only capture-quality signals derived purely from a memory's
/// existing fields. No score is invented and no backend data is required; this
/// only restates what the DTO already carries so Inbox can surface a calm cue for
/// captures that arrived without any organizing metadata.
struct MemoryCaptureQuality: Equatable {
    let isLinkedToProject: Bool
    let hasTags: Bool
    let hasSource: Bool

    init(memory: MemoryDTO) {
        isLinkedToProject = memory.projectId != nil
        hasTags = !memory.tags.isEmpty
        hasSource = !(memory.sourceUrl?.isEmpty ?? true)
    }

    /// Flags a capture for review only when it has no organizing metadata at all —
    /// not linked to a project, untagged, and without a source. These bare rows
    /// are the ones most likely to need filing later, and the signal is fully
    /// deterministic, so the cue stays reliable rather than speculative.
    var needsReview: Bool {
        !isLinkedToProject && !hasTags && !hasSource
    }
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

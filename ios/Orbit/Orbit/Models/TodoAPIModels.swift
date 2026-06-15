import Foundation

struct TodoDTO: Decodable, Identifiable, Hashable {
    let id: UUID
    var title: String
    var notes: String?
    var dueDate: Date?
    var projectId: UUID?
    var isComplete: Bool
    var createdAt: Date
    var updatedAt: Date
}

struct TodoCreateRequest: Encodable {
    var title: String
    var notes: String?
    var dueDate: Date?
    var projectId: UUID?
    var isComplete: Bool = false
}

struct TodoUpdateRequest: Encodable {
    var title: String?
    var notes: String?
    var dueDate: Date?
    var projectId: UUID?
    var isComplete: Bool?

    enum CodingKeys: String, CodingKey {
        case title
        case notes
        case dueDate
        case projectId
        case isComplete
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(title, forKey: .title)
        try container.encodeIfPresent(notes, forKey: .notes)
        try container.encodeIfPresent(dueDate, forKey: .dueDate)
        try container.encodeIfPresent(projectId, forKey: .projectId)
        try container.encodeIfPresent(isComplete, forKey: .isComplete)
    }
}


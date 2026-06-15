import Foundation

struct MoodDTO: Decodable, Identifiable, Hashable, Sendable {
    let id: UUID
    var mood: String
    var energy: Int
    var notes: String?
    var checkInDate: Date
    var createdAt: Date
    var updatedAt: Date
}

struct MoodCreateRequest: Encodable, Sendable {
    var mood: String
    var energy: Int
    var notes: String?
    var checkInDate: Date?
}

struct MoodUpdateRequest: Encodable, Sendable {
    var mood: String?
    var energy: Int?
    var notes: String?
    var checkInDate: Date?

    enum CodingKeys: String, CodingKey {
        case mood
        case energy
        case notes
        case checkInDate
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(mood, forKey: .mood)
        try container.encodeIfPresent(energy, forKey: .energy)
        try container.encodeIfPresent(notes, forKey: .notes)
        try container.encodeIfPresent(checkInDate, forKey: .checkInDate)
    }
}

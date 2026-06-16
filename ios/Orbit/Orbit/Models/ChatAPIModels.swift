import Foundation

struct ChatSessionDTO: Decodable, Identifiable, Hashable, Sendable {
    let id: UUID
    var title: String?
    var createdAt: Date
    var updatedAt: Date
}

struct ChatMessageDTO: Decodable, Identifiable, Hashable, Sendable {
    let id: UUID
    var sessionId: UUID
    var role: String
    var content: String
    var createdAt: Date
}

struct AskRequest: Encodable, Sendable {
    var question: String
    var sessionId: UUID?
    var includeContext: Bool = true
}

struct AskResponse: Decodable, Sendable {
    var session: ChatSessionDTO
    var userMessage: ChatMessageDTO
    var assistantMessage: ChatMessageDTO
    var answer: String
}

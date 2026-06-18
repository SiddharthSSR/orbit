import Foundation

struct ChatSessionDTO: Decodable, Identifiable, Hashable, Sendable {
    let id: UUID
    var title: String?
    var createdAt: Date
    var updatedAt: Date

    var readableTitle: String {
        Self.normalizedTitle(title)
    }

    func displayTitle(maxLength: Int = 40) -> String {
        let normalized = readableTitle
        guard maxLength > 1, normalized.count > maxLength else { return normalized }
        let prefix = String(normalized.prefix(maxLength - 1))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(prefix)…"
    }

    private static func normalizedTitle(_ title: String?) -> String {
        guard let title else { return "New Ask" }
        let normalized = title
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return normalized.isEmpty ? "New Ask" : normalized
    }
}

struct ChatMessageDTO: Decodable, Identifiable, Hashable, Sendable {
    let id: UUID
    var sessionId: UUID
    var role: String
    var content: String
    var createdAt: Date
}

enum RetrievalMode: String, Codable, Equatable, Sendable {
    case keyword
    case hybrid
}

struct RetrievalDiagnostics: Decodable, Equatable, Sendable {
    var retrievalMode: RetrievalMode
    var memoryTopK: Int
    var minVectorScore: Double
    var vectorAttempted: Bool
    var vectorResultCount: Int
    var vectorError: String?
    var fallbackUsed: Bool
    var contextBuildMs: Double
}

struct AskRequest: Encodable, Sendable {
    var question: String
    var sessionId: UUID?
    var includeContext: Bool = true
    var retrievalMode: RetrievalMode = .keyword
    var memoryTopK: Int = 5
    var minVectorScore: Double = 0.0
}

struct AskResponse: Decodable, Sendable {
    var session: ChatSessionDTO
    var userMessage: ChatMessageDTO
    var assistantMessage: ChatMessageDTO
    var answer: String
    var retrievalDiagnostics: RetrievalDiagnostics? = nil
}

struct AskContextPreviewRequest: Encodable, Sendable {
    var question: String
    var includeContext: Bool = true
    var retrievalMode: RetrievalMode = .keyword
    var memoryTopK: Int = 5
    var minVectorScore: Double = 0.0
}

struct AskContextPreviewResponse: Decodable, Equatable, Sendable {
    var question: String
    var includeContext: Bool
    var context: String
    var contextSections: [String]
    var retrievalDiagnostics: RetrievalDiagnostics? = nil
}

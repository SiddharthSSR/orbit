import Foundation

actor MockChatAPIClient: ChatAPIClientProtocol {
    private var sessions: [ChatSessionDTO]
    private var messagesBySession: [UUID: [ChatMessageDTO]]

    init(
        sessions: [ChatSessionDTO] = MockChatAPIClient.previewSessions,
        messagesBySession: [UUID: [ChatMessageDTO]] = [:]
    ) {
        self.sessions = sessions
        if messagesBySession.isEmpty {
            self.messagesBySession = Dictionary(
                uniqueKeysWithValues: sessions.map { session in
                    (session.id, MockChatAPIClient.previewMessages(sessionId: session.id))
                }
            )
        } else {
            self.messagesBySession = messagesBySession
        }
    }

    func ask(_ payload: AskRequest) async throws -> AskResponse {
        let now = Date()
        let session: ChatSessionDTO

        if let sessionId = payload.sessionId {
            guard let existingIndex = sessions.firstIndex(where: { $0.id == sessionId }) else {
                throw OrbitAPIError.requestFailed(statusCode: 404, message: "Chat session not found")
            }
            sessions[existingIndex].updatedAt = now
            session = sessions[existingIndex]
        } else {
            let title = makeTitle(from: payload.question)
            let newSession = ChatSessionDTO(id: UUID(), title: title, createdAt: now, updatedAt: now)
            sessions.insert(newSession, at: 0)
            messagesBySession[newSession.id] = []
            session = newSession
        }

        let userMessage = ChatMessageDTO(
            id: UUID(),
            sessionId: session.id,
            role: "user",
            content: payload.question,
            createdAt: now
        )
        let assistantContent = "Based on available Orbit context, here is a mock answer for: \(payload.question)"
        let assistantMessage = ChatMessageDTO(
            id: UUID(),
            sessionId: session.id,
            role: "assistant",
            content: assistantContent,
            createdAt: now.addingTimeInterval(0.001)
        )

        messagesBySession[session.id, default: []].append(contentsOf: [userMessage, assistantMessage])
        sessions.sort { $0.updatedAt > $1.updatedAt }

        return AskResponse(
            session: session,
            userMessage: userMessage,
            assistantMessage: assistantMessage,
            answer: assistantContent
        )
    }

    func listChatSessions() async throws -> [ChatSessionDTO] {
        sessions.sorted { $0.updatedAt > $1.updatedAt }
    }

    func listMessages(sessionId: UUID) async throws -> [ChatMessageDTO] {
        guard sessions.contains(where: { $0.id == sessionId }) else {
            throw OrbitAPIError.requestFailed(statusCode: 404, message: "Chat session not found")
        }
        return messagesBySession[sessionId, default: []].sorted { $0.createdAt < $1.createdAt }
    }

    private func makeTitle(from question: String) -> String {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 80 else { return trimmed }
        return "\(String(trimmed.prefix(77)).trimmingCharacters(in: .whitespacesAndNewlines))..."
    }

    private static let previewSessions: [ChatSessionDTO] = {
        let now = Date()
        return [
            ChatSessionDTO(
                id: UUID(),
                title: "What should I focus on today?",
                createdAt: now.addingTimeInterval(-600),
                updatedAt: now.addingTimeInterval(-300)
            ),
            ChatSessionDTO(
                id: UUID(),
                title: "Upcoming bills",
                createdAt: now.addingTimeInterval(-3_600),
                updatedAt: now.addingTimeInterval(-3_000)
            )
        ]
    }()

    private static func previewMessages(sessionId: UUID) -> [ChatMessageDTO] {
        let now = Date()
        return [
            ChatMessageDTO(
                id: UUID(),
                sessionId: sessionId,
                role: "user",
                content: "What should I focus on today?",
                createdAt: now.addingTimeInterval(-120)
            ),
            ChatMessageDTO(
                id: UUID(),
                sessionId: sessionId,
                role: "assistant",
                content: "Based on available Orbit context, start with the most urgent open todo and check upcoming bills.",
                createdAt: now.addingTimeInterval(-119)
            )
        ]
    }
}

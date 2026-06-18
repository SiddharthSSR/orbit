import Foundation

actor MockChatAPIClient: ChatAPIClientProtocol {
    private var sessions: [ChatSessionDTO]
    private var messagesBySession: [UUID: [ChatMessageDTO]]
    private var askRequests: [AskRequest] = []
    private var previewRequests: [AskContextPreviewRequest] = []
    private var deletedSessionIds: [UUID] = []

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
        askRequests.append(payload)
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
            answer: assistantContent,
            retrievalDiagnostics: diagnostics(
                mode: payload.retrievalMode,
                memoryTopK: payload.memoryTopK,
                minVectorScore: payload.minVectorScore,
                includeContext: payload.includeContext
            )
        )
    }

    func previewAskContext(_ payload: AskContextPreviewRequest) async throws -> AskContextPreviewResponse {
        previewRequests.append(payload)
        guard payload.includeContext else {
            return AskContextPreviewResponse(
                question: payload.question,
                includeContext: false,
                context: "",
                contextSections: [],
                retrievalDiagnostics: nil
            )
        }

        let sections = ["Today", "Open todos", "Recent memory"]
        let context = """
        Today:
        - 2026-06-17

        Open todos:
        - [Due today] Review Orbit Ask context

        Recent memory:
        - AI retrieval notes (note) [ai]: Lightweight relevance before embeddings
        """

        return AskContextPreviewResponse(
            question: payload.question,
            includeContext: true,
            context: context,
            contextSections: sections,
            retrievalDiagnostics: diagnostics(
                mode: payload.retrievalMode,
                memoryTopK: payload.memoryTopK,
                minVectorScore: payload.minVectorScore,
                includeContext: true
            )
        )
    }

    func lastAskRequest() -> AskRequest? {
        askRequests.last
    }

    func lastPreviewRequest() -> AskContextPreviewRequest? {
        previewRequests.last
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

    func deleteChatSession(id: UUID) async throws {
        guard sessions.contains(where: { $0.id == id }) else {
            throw OrbitAPIError.requestFailed(statusCode: 404, message: "Chat session not found")
        }
        deletedSessionIds.append(id)
        sessions.removeAll { $0.id == id }
        messagesBySession[id] = nil
    }

    func deletedSessions() -> [UUID] {
        deletedSessionIds
    }

    private func makeTitle(from question: String) -> String {
        var normalized = question
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let quotePairs: Set<String> = ["\"\"", "''", "“”", "‘’"]
        if let first = normalized.first,
           let last = normalized.last,
           quotePairs.contains("\(first)\(last)") {
            normalized = String(normalized.dropFirst().dropLast())
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !normalized.isEmpty else { return "New Ask" }
        guard normalized.count > 60 else { return normalized }
        let prefix = String(normalized.prefix(59))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(prefix)…"
    }

    private func diagnostics(
        mode: RetrievalMode,
        memoryTopK: Int,
        minVectorScore: Double,
        includeContext: Bool
    ) -> RetrievalDiagnostics? {
        guard includeContext else { return nil }
        let isHybrid = mode == .hybrid
        return RetrievalDiagnostics(
            retrievalMode: mode,
            memoryTopK: memoryTopK,
            minVectorScore: minVectorScore,
            vectorAttempted: isHybrid,
            vectorResultCount: isHybrid ? 2 : 0,
            vectorError: nil,
            fallbackUsed: false,
            contextBuildMs: isHybrid ? 2.4 : 1.2
        )
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

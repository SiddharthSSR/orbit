import XCTest
@testable import Orbit

@MainActor
final class AskViewModelTests: XCTestCase {
    func testLoadSessionsLoadsMockSessions() async {
        let sessions = [makeSession(title: "Focus today"), makeSession(title: "Bills")]
        let viewModel = AskViewModel(apiClient: MockChatAPIClient(sessions: sessions, messagesBySession: [:]))

        await viewModel.loadSessions()

        XCTAssertEqual(viewModel.sessions.map(\.title), ["Focus today", "Bills"])
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testSendQuestionCreatesNewSessionWhenNoneSelected() async {
        let viewModel = AskViewModel(apiClient: MockChatAPIClient(sessions: [], messagesBySession: [:]))
        viewModel.draftQuestion = " What should I focus on today? "

        await viewModel.sendQuestion()

        XCTAssertNotNil(viewModel.selectedSession)
        XCTAssertEqual(viewModel.sessions.count, 1)
        XCTAssertEqual(viewModel.selectedSession?.title, "What should I focus on today?")
        XCTAssertNil(viewModel.errorMessage)
    }

    func testSendQuestionAppendsUserAndAssistantMessages() async {
        let viewModel = AskViewModel(apiClient: MockChatAPIClient(sessions: [], messagesBySession: [:]))
        viewModel.draftQuestion = "What bills are coming up?"

        await viewModel.sendQuestion()

        XCTAssertEqual(viewModel.messages.count, 2)
        XCTAssertEqual(viewModel.messages.map(\.role), ["user", "assistant"])
        XCTAssertEqual(viewModel.messages.first?.content, "What bills are coming up?")
        XCTAssertTrue(viewModel.messages.last?.content.contains("available Orbit context") == true)
    }

    func testSendQuestionClearsDraft() async {
        let viewModel = AskViewModel(apiClient: MockChatAPIClient(sessions: [], messagesBySession: [:]))
        viewModel.draftQuestion = "How are my projects going?"

        await viewModel.sendQuestion()

        XCTAssertEqual(viewModel.draftQuestion, "")
    }

    func testSelectSessionLoadsMessages() async {
        let session = makeSession(title: "Existing")
        let messages = [
            makeMessage(sessionId: session.id, role: "user", content: "Question"),
            makeMessage(sessionId: session.id, role: "assistant", content: "Answer")
        ]
        let viewModel = AskViewModel(
            apiClient: MockChatAPIClient(
                sessions: [session],
                messagesBySession: [session.id: messages]
            )
        )

        await viewModel.selectSession(session)

        XCTAssertEqual(viewModel.selectedSession?.id, session.id)
        XCTAssertEqual(viewModel.messages.map(\.content), ["Question", "Answer"])
        XCTAssertNil(viewModel.errorMessage)
    }

    func testStartNewSessionClearsSelectionAndMessages() async {
        let session = makeSession(title: "Existing")
        let viewModel = AskViewModel(
            apiClient: MockChatAPIClient(
                sessions: [session],
                messagesBySession: [session.id: [makeMessage(sessionId: session.id)]]
            )
        )

        await viewModel.selectSession(session)
        viewModel.draftQuestion = "Draft"
        viewModel.startNewSession()

        XCTAssertNil(viewModel.selectedSession)
        XCTAssertTrue(viewModel.messages.isEmpty)
        XCTAssertEqual(viewModel.draftQuestion, "")
        XCTAssertNil(viewModel.errorMessage)
    }

    func testBlankQuestionIsIgnored() async {
        let viewModel = AskViewModel(apiClient: MockChatAPIClient(sessions: [], messagesBySession: [:]))
        viewModel.draftQuestion = "   \n\t "

        await viewModel.sendQuestion()

        XCTAssertNil(viewModel.selectedSession)
        XCTAssertTrue(viewModel.sessions.isEmpty)
        XCTAssertTrue(viewModel.messages.isEmpty)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testErrorStateIsSetWhenAPIThrows() async {
        let viewModel = AskViewModel(apiClient: FailingChatAPIClient())

        await viewModel.loadSessions()

        XCTAssertEqual(viewModel.errorMessage, "Expected chat API failure.")
        XCTAssertFalse(viewModel.isLoading)
    }

    private func makeSession(title: String) -> ChatSessionDTO {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        return ChatSessionDTO(id: UUID(), title: title, createdAt: now, updatedAt: now)
    }

    private func makeMessage(
        sessionId: UUID,
        role: String = "user",
        content: String = "Question"
    ) -> ChatMessageDTO {
        ChatMessageDTO(
            id: UUID(),
            sessionId: sessionId,
            role: role,
            content: content,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }
}

private struct FailingChatAPIClient: ChatAPIClientProtocol {
    func ask(_ payload: AskRequest) async throws -> AskResponse {
        throw FailingChatAPIError.expectedFailure
    }

    func listChatSessions() async throws -> [ChatSessionDTO] {
        throw FailingChatAPIError.expectedFailure
    }

    func listMessages(sessionId: UUID) async throws -> [ChatMessageDTO] {
        throw FailingChatAPIError.expectedFailure
    }
}

private enum FailingChatAPIError: LocalizedError {
    case expectedFailure

    var errorDescription: String? {
        "Expected chat API failure."
    }
}

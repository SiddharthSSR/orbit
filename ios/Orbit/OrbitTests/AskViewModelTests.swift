import XCTest
@testable import Orbit

@MainActor
final class AskViewModelTests: XCTestCase {
    func testDefaultsToKeywordRetrieval() {
        let viewModel = makeViewModel(MockChatAPIClient(sessions: [], messagesBySession: [:]))

        XCTAssertFalse(viewModel.useHybridRetrieval)
        XCTAssertEqual(viewModel.memoryTopK, 5)
        XCTAssertEqual(viewModel.minVectorScore, 0.0)
        XCTAssertNil(viewModel.latestRetrievalDiagnostics)
    }

    func testLoadSessionsLoadsMockSessions() async {
        let sessions = [makeSession(title: "Focus today"), makeSession(title: "Bills")]
        let viewModel = makeViewModel(MockChatAPIClient(sessions: sessions, messagesBySession: [:]))

        await viewModel.loadSessions()

        XCTAssertEqual(viewModel.sessions.map(\.title), ["Focus today", "Bills"])
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testSendQuestionCreatesNewSessionWhenNoneSelected() async {
        let viewModel = makeViewModel(MockChatAPIClient(sessions: [], messagesBySession: [:]))
        viewModel.draftQuestion = " What should I focus on today? "

        await viewModel.sendQuestion()

        XCTAssertNotNil(viewModel.selectedSession)
        XCTAssertEqual(viewModel.sessions.count, 1)
        XCTAssertEqual(viewModel.selectedSession?.title, "What should I focus on today?")
        XCTAssertNil(viewModel.errorMessage)
    }

    func testSendQuestionAppendsUserAndAssistantMessages() async {
        let viewModel = makeViewModel(MockChatAPIClient(sessions: [], messagesBySession: [:]))
        viewModel.draftQuestion = "What bills are coming up?"

        await viewModel.sendQuestion()

        XCTAssertEqual(viewModel.messages.count, 2)
        XCTAssertEqual(viewModel.messages.map(\.role), ["user", "assistant"])
        XCTAssertEqual(viewModel.messages.first?.content, "What bills are coming up?")
        XCTAssertTrue(viewModel.messages.last?.content.contains("available Orbit context") == true)
    }

    func testSendQuestionStoresContextSummaryForAssistantOnly() async {
        let viewModel = makeViewModel(MockChatAPIClient(sessions: [], messagesBySession: [:]))
        viewModel.draftQuestion = "What did I save about AI?"

        await viewModel.sendQuestion()

        let userMessage = viewModel.messages[0]
        let assistantMessage = viewModel.messages[1]
        XCTAssertNil(viewModel.contextSummary(for: userMessage))
        XCTAssertEqual(
            viewModel.contextSummary(for: assistantMessage),
            "Context used: Today, Open todos, Recent memory"
        )
    }

    func testSendQuestionWithoutContextDoesNotStoreContextSummary() async {
        let viewModel = makeViewModel(MockChatAPIClient(sessions: [], messagesBySession: [:]))
        viewModel.includeContext = false
        viewModel.draftQuestion = "What did I save about AI?"

        await viewModel.sendQuestion()

        XCTAssertNil(viewModel.contextSummary(for: viewModel.messages[1]))
    }

    func testSendQuestionMapsSuggestedActionsToAssistantOnly() async {
        let viewModel = makeViewModel(MockChatAPIClient(sessions: [], messagesBySession: [:]))
        viewModel.draftQuestion = "What bills are coming up?"

        await viewModel.sendQuestion()

        XCTAssertTrue(viewModel.suggestedActions(for: viewModel.messages[0]).isEmpty)
        XCTAssertEqual(viewModel.suggestedActions(for: viewModel.messages[1]).map(\.type), ["review_bills"])
    }

    func testSendQuestionClearsDraft() async {
        let viewModel = makeViewModel(MockChatAPIClient(sessions: [], messagesBySession: [:]))
        viewModel.draftQuestion = "How are my projects going?"

        await viewModel.sendQuestion()

        XCTAssertEqual(viewModel.draftQuestion, "")
    }

    func testSendQuestionUsesKeywordRetrievalByDefault() async {
        let client = MockChatAPIClient(sessions: [], messagesBySession: [:])
        let viewModel = makeViewModel(client)
        viewModel.draftQuestion = "What did I save about AI?"

        await viewModel.sendQuestion()

        let request = await client.lastAskRequest()
        XCTAssertEqual(request?.retrievalMode, .keyword)
        XCTAssertEqual(request?.memoryTopK, 5)
        XCTAssertEqual(request?.minVectorScore, 0.0)
        XCTAssertEqual(viewModel.latestRetrievalDiagnostics?.retrievalMode, .keyword)
    }

    func testSendQuestionUsesConfiguredHybridRetrieval() async {
        let client = MockChatAPIClient(sessions: [], messagesBySession: [:])
        let viewModel = makeViewModel(client)
        viewModel.draftQuestion = "What did I save about AI?"
        viewModel.useHybridRetrieval = true
        viewModel.memoryTopK = 8
        viewModel.minVectorScore = 0.25

        await viewModel.sendQuestion()

        let request = await client.lastAskRequest()
        XCTAssertEqual(request?.retrievalMode, .hybrid)
        XCTAssertEqual(request?.memoryTopK, 8)
        XCTAssertEqual(request?.minVectorScore, 0.25)
        XCTAssertEqual(viewModel.latestRetrievalDiagnostics?.retrievalMode, .hybrid)
        XCTAssertEqual(viewModel.latestRetrievalDiagnostics?.vectorResultCount, 2)
    }

    func testSelectSessionLoadsMessages() async {
        let session = makeSession(title: "Existing")
        let messages = [
            makeMessage(sessionId: session.id, role: "user", content: "Question"),
            makeMessage(sessionId: session.id, role: "assistant", content: "Answer")
        ]
        let viewModel = makeViewModel(
            MockChatAPIClient(
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
        let viewModel = makeViewModel(
            MockChatAPIClient(
                sessions: [session],
                messagesBySession: [session.id: [makeMessage(sessionId: session.id)]]
            )
        )

        await viewModel.selectSession(session)
        viewModel.draftQuestion = "Draft"
        viewModel.useHybridRetrieval = true
        viewModel.includeContext = false
        viewModel.startNewSession()

        XCTAssertNil(viewModel.selectedSession)
        XCTAssertTrue(viewModel.messages.isEmpty)
        XCTAssertEqual(viewModel.draftQuestion, "")
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertNil(viewModel.contextPreview)
        XCTAssertNil(viewModel.latestRetrievalDiagnostics)
        XCTAssertTrue(viewModel.answerContextSummaries.isEmpty)
        XCTAssertTrue(viewModel.answerSuggestedActions.isEmpty)
        XCTAssertTrue(viewModel.useHybridRetrieval)
        XCTAssertFalse(viewModel.includeContext)
    }

    func testSessionDisplayTitleFallsBackForMissingOrBlankTitle() {
        XCTAssertEqual(makeSession(title: nil).displayTitle(), "New Ask")
        XCTAssertEqual(makeSession(title: "  \n ").displayTitle(), "New Ask")
    }

    func testSessionDisplayTitleCollapsesWhitespaceAndTruncatesCleanly() {
        let session = makeSession(title: "  A   readable\nchat title that is deliberately long  ")

        XCTAssertEqual(session.displayTitle(maxLength: 24), "A readable chat title t…")
        XCTAssertEqual(session.displayTitle(maxLength: 24).count, 24)
    }

    func testDeleteSessionRemovesItFromListAndRecordsOnClient() async {
        let kept = makeSession(title: "Keep")
        let removed = makeSession(title: "Remove")
        let client = MockChatAPIClient(
            sessions: [kept, removed],
            messagesBySession: [
                kept.id: [makeMessage(sessionId: kept.id)],
                removed.id: [makeMessage(sessionId: removed.id)],
            ]
        )
        let viewModel = makeViewModel(client)
        await viewModel.loadSessions()

        await viewModel.deleteSession(removed)

        XCTAssertEqual(viewModel.sessions.map(\.id), [kept.id])
        let deleted = await client.deletedSessions()
        XCTAssertEqual(deleted, [removed.id])
        XCTAssertNil(viewModel.errorMessage)
    }

    func testDeletingSelectedSessionClearsConversation() async {
        let session = makeSession(title: "Active")
        let client = MockChatAPIClient(
            sessions: [session],
            messagesBySession: [session.id: [makeMessage(sessionId: session.id)]]
        )
        let viewModel = makeViewModel(client)
        await viewModel.selectSession(session)
        XCTAssertFalse(viewModel.messages.isEmpty)

        await viewModel.deleteSession(session)

        XCTAssertNil(viewModel.selectedSession)
        XCTAssertTrue(viewModel.messages.isEmpty)
        XCTAssertTrue(viewModel.sessions.isEmpty)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testDeletingUnselectedSessionKeepsCurrentConversation() async {
        let active = makeSession(title: "Active")
        let other = makeSession(title: "Other")
        let client = MockChatAPIClient(
            sessions: [active, other],
            messagesBySession: [
                active.id: [makeMessage(sessionId: active.id)],
                other.id: [makeMessage(sessionId: other.id)],
            ]
        )
        let viewModel = makeViewModel(client)
        await viewModel.loadSessions()
        await viewModel.selectSession(active)

        await viewModel.deleteSession(other)

        XCTAssertEqual(viewModel.selectedSession?.id, active.id)
        XCTAssertFalse(viewModel.messages.isEmpty)
        XCTAssertEqual(viewModel.sessions.map(\.id), [active.id])
    }

    func testClearCurrentSessionDeletesSelectedSession() async {
        let session = makeSession(title: "Active")
        let client = MockChatAPIClient(
            sessions: [session],
            messagesBySession: [session.id: [makeMessage(sessionId: session.id)]]
        )
        let viewModel = makeViewModel(client)
        await viewModel.selectSession(session)

        await viewModel.clearCurrentSession()

        let deleted = await client.deletedSessions()
        XCTAssertEqual(deleted, [session.id])
        XCTAssertNil(viewModel.selectedSession)
        XCTAssertTrue(viewModel.messages.isEmpty)
    }

    func testDeleteSessionSetsErrorMessageOnFailure() async {
        let session = makeSession(title: "Doomed")
        let viewModel = makeViewModel(FailingChatAPIClient())

        await viewModel.deleteSession(session)

        XCTAssertEqual(viewModel.errorMessage, "Expected chat API failure.")
    }

    func testBlankQuestionIsIgnored() async {
        let viewModel = makeViewModel(MockChatAPIClient(sessions: [], messagesBySession: [:]))
        viewModel.draftQuestion = "   \n\t "

        await viewModel.sendQuestion()

        XCTAssertNil(viewModel.selectedSession)
        XCTAssertTrue(viewModel.sessions.isEmpty)
        XCTAssertTrue(viewModel.messages.isEmpty)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testErrorStateIsSetWhenAPIThrows() async {
        let viewModel = makeViewModel(FailingChatAPIClient())

        await viewModel.loadSessions()

        XCTAssertEqual(viewModel.errorMessage, "Expected chat API failure.")
        XCTAssertFalse(viewModel.isLoading)
    }

    func testPreviewContextLoadsPreview() async {
        let viewModel = makeViewModel(MockChatAPIClient(sessions: [], messagesBySession: [:]))
        viewModel.draftQuestion = "What did I save about AI?"

        await viewModel.previewContext()

        XCTAssertEqual(viewModel.contextPreview?.question, "What did I save about AI?")
        XCTAssertEqual(viewModel.contextPreview?.contextSections, ["Today", "Open todos", "Recent memory"])
        XCTAssertTrue(viewModel.contextPreview?.context.contains("AI retrieval notes") == true)
        XCTAssertFalse(viewModel.isPreviewLoading)
        XCTAssertNil(viewModel.previewErrorMessage)
    }

    func testPreviewContextUsesSameHybridRetrievalSettings() async {
        let client = MockChatAPIClient(sessions: [], messagesBySession: [:])
        let viewModel = makeViewModel(client)
        viewModel.draftQuestion = "What did I save about AI?"
        viewModel.useHybridRetrieval = true
        viewModel.memoryTopK = 7
        viewModel.minVectorScore = 0.15

        await viewModel.previewContext()

        let request = await client.lastPreviewRequest()
        XCTAssertEqual(request?.retrievalMode, .hybrid)
        XCTAssertEqual(request?.memoryTopK, 7)
        XCTAssertEqual(request?.minVectorScore, 0.15)
        XCTAssertEqual(viewModel.latestRetrievalDiagnostics?.retrievalMode, .hybrid)
    }

    func testPreviewContextIgnoresBlankDraft() async {
        let viewModel = makeViewModel(MockChatAPIClient(sessions: [], messagesBySession: [:]))
        viewModel.draftQuestion = "   \n\t "

        await viewModel.previewContext()

        XCTAssertNil(viewModel.contextPreview)
        XCTAssertNil(viewModel.previewErrorMessage)
    }

    func testPreviewContextRespectsIncludeContextFalse() async {
        let viewModel = makeViewModel(MockChatAPIClient(sessions: [], messagesBySession: [:]))
        viewModel.draftQuestion = "What should I focus on today?"
        viewModel.includeContext = false

        await viewModel.previewContext()

        XCTAssertEqual(viewModel.contextPreview?.includeContext, false)
        XCTAssertEqual(viewModel.contextPreview?.context, "")
        XCTAssertEqual(viewModel.contextPreview?.contextSections, [])
    }

    func testPreviewContextDoesNotAppendMessages() async {
        let session = makeSession(title: "Existing")
        let messages = [makeMessage(sessionId: session.id)]
        let viewModel = makeViewModel(
            MockChatAPIClient(
                sessions: [session],
                messagesBySession: [session.id: messages]
            )
        )
        await viewModel.selectSession(session)
        viewModel.draftQuestion = "What did I save about AI?"

        await viewModel.previewContext()

        XCTAssertEqual(viewModel.selectedSession?.id, session.id)
        XCTAssertEqual(viewModel.messages.count, 1)
        XCTAssertEqual(viewModel.messages.first?.content, "Question")
    }

    func testPreviewContextSetsPreviewErrorMessageOnFailure() async {
        let viewModel = makeViewModel(FailingChatAPIClient())
        viewModel.draftQuestion = "What did I save about AI?"

        await viewModel.previewContext()

        XCTAssertEqual(viewModel.previewErrorMessage, "Expected chat API failure.")
        XCTAssertFalse(viewModel.isPreviewLoading)
    }

    func testContextConfidenceIsNoContextForEmptySections() {
        let confidence = AskViewModel.contextConfidence(
            for: AskContextPreviewResponse(
                question: "What should I do?",
                includeContext: true,
                context: "",
                contextSections: []
            )
        )

        XCTAssertEqual(confidence, .noContext)
        XCTAssertEqual(confidence.label, "No context")
    }

    func testContextConfidenceIsLowContextForOnlyGenericOrEmptySections() {
        let confidence = AskViewModel.contextConfidence(
            for: AskContextPreviewResponse(
                question: "What should I do?",
                includeContext: true,
                context: """
                Today:
                - 2026-06-17

                Open todos:
                - None

                Unpaid bills:
                - None
                """,
                contextSections: ["Today", "Open todos", "Unpaid bills"]
            )
        )

        XCTAssertEqual(confidence, .lowContext)
    }

    func testContextConfidenceIsReadyWhenDataSectionsIncludeUsableContext() {
        let confidence = AskViewModel.contextConfidence(
            for: AskContextPreviewResponse(
                question: "What did I save about AI?",
                includeContext: true,
                context: """
                Today:
                - 2026-06-17

                Recent memory:
                - AI retrieval notes (note) [ai]: Lightweight relevance before embeddings
                """,
                contextSections: ["Today", "Recent memory"]
            )
        )

        XCTAssertEqual(confidence, .ready)
    }

    func testContextConfidenceIsNoContextWhenIncludeContextIsFalse() {
        let confidence = AskViewModel.contextConfidence(
            for: AskContextPreviewResponse(
                question: "What should I do?",
                includeContext: false,
                context: "",
                contextSections: []
            )
        )

        XCTAssertEqual(confidence, .noContext)
    }

    // MARK: - Persistence

    func testDefaultPreferencesAreKeywordOffWhenNoSavedValuesExist() {
        let defaults = makeIsolatedDefaults()
        let viewModel = makeViewModel(
            MockChatAPIClient(sessions: [], messagesBySession: [:]),
            defaults: defaults
        )

        XCTAssertFalse(viewModel.useHybridRetrieval)
        XCTAssertEqual(viewModel.memoryTopK, 5)
        XCTAssertEqual(viewModel.minVectorScore, 0.0)
    }

    func testTogglingHybridPersistsTrue() {
        let defaults = makeIsolatedDefaults()
        let viewModel = makeViewModel(
            MockChatAPIClient(sessions: [], messagesBySession: [:]),
            defaults: defaults
        )

        viewModel.useHybridRetrieval = true

        XCTAssertTrue(AskRetrievalPreferences(defaults: defaults).useHybridRetrieval)
    }

    func testRecreatedViewModelRestoresSavedHybridPreference() {
        let defaults = makeIsolatedDefaults()
        let first = makeViewModel(
            MockChatAPIClient(sessions: [], messagesBySession: [:]),
            defaults: defaults
        )
        first.useHybridRetrieval = true

        let restored = makeViewModel(
            MockChatAPIClient(sessions: [], messagesBySession: [:]),
            defaults: defaults
        )

        XCTAssertTrue(restored.useHybridRetrieval)
    }

    func testMemoryTopKAndMinVectorScorePersistWhenSetProgrammatically() {
        let defaults = makeIsolatedDefaults()
        let viewModel = makeViewModel(
            MockChatAPIClient(sessions: [], messagesBySession: [:]),
            defaults: defaults
        )

        viewModel.memoryTopK = 8
        viewModel.minVectorScore = 0.25

        let restored = makeViewModel(
            MockChatAPIClient(sessions: [], messagesBySession: [:]),
            defaults: defaults
        )

        XCTAssertEqual(restored.memoryTopK, 8)
        XCTAssertEqual(restored.minVectorScore, 0.25)
    }

    func testDiagnosticsAreNotPersisted() async {
        let defaults = makeIsolatedDefaults()
        let viewModel = makeViewModel(
            MockChatAPIClient(sessions: [], messagesBySession: [:]),
            defaults: defaults
        )
        viewModel.draftQuestion = "What did I save about AI?"
        viewModel.useHybridRetrieval = true

        await viewModel.sendQuestion()
        XCTAssertNotNil(viewModel.latestRetrievalDiagnostics)

        let restored = makeViewModel(
            MockChatAPIClient(sessions: [], messagesBySession: [:]),
            defaults: defaults
        )

        XCTAssertNil(restored.latestRetrievalDiagnostics)
    }

    // MARK: - Helpers

    /// Creates an `AskViewModel` with an isolated `UserDefaults` suite so tests
    /// never read from or write to the real app defaults. Pass a shared
    /// `defaults` to exercise persistence across recreated view models.
    private func makeViewModel(
        _ apiClient: any ChatAPIClientProtocol,
        defaults: UserDefaults? = nil
    ) -> AskViewModel {
        AskViewModel(
            apiClient: apiClient,
            preferences: AskRetrievalPreferences(defaults: defaults ?? makeIsolatedDefaults())
        )
    }

    private func makeIsolatedDefaults() -> UserDefaults {
        let suiteName = "AskViewModelTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func makeSession(title: String?) -> ChatSessionDTO {
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

final class AskAnswerMarkdownTests: XCTestCase {
    func testParsesBoldLabel() {
        let attributed = AskAnswerMarkdown.attributedLine("**Bills:** due soon")

        XCTAssertEqual(String(attributed.characters), "Bills: due soon")
        let hasBold = attributed.runs.contains { run in
            run.inlinePresentationIntent?.contains(.stronglyEmphasized) ?? false
        }
        XCTAssertTrue(hasBold)
    }

    func testParsesLinkAsTappableRun() {
        let attributed = AskAnswerMarkdown.attributedLine("See [docs](https://example.com)")

        XCTAssertEqual(String(attributed.characters), "See docs")
        let link = attributed.runs.compactMap(\.link).first
        XCTAssertEqual(link, URL(string: "https://example.com"))
    }

    func testConvertsLeadingBulletMarkerToGlyph() {
        let dash = AskAnswerMarkdown.attributedLine("- Furlenco Furniture Rent")
        let star = AskAnswerMarkdown.attributedLine("* Credit Card Payment")

        XCTAssertTrue(String(dash.characters).hasPrefix("•  Furlenco Furniture Rent"))
        XCTAssertTrue(String(star.characters).hasPrefix("•  Credit Card Payment"))
    }

    func testPlainTextRendersAndFallsBack() {
        let attributed = AskAnswerMarkdown.attributedLine("Just a plain sentence.")

        XCTAssertEqual(String(attributed.characters), "Just a plain sentence.")
        let hasBold = attributed.runs.contains { run in
            run.inlinePresentationIntent?.contains(.stronglyEmphasized) ?? false
        }
        XCTAssertFalse(hasBold)
    }

    func testDisplayLinesTrimsAndDropsEmptyLines() {
        let content = "You have 2 bills.\n\n- Credit Card Payment\n  - Furlenco\n"

        XCTAssertEqual(
            AskAnswerMarkdown.displayLines(from: content),
            ["You have 2 bills.", "- Credit Card Payment", "- Furlenco"]
        )
    }

    func testNextStepDetection() {
        XCTAssertTrue(AskAnswerMarkdown.isNextStep("Next step: pay the overdue bill"))
        XCTAssertTrue(AskAnswerMarkdown.isNextStep("next steps: review todos"))
        XCTAssertFalse(AskAnswerMarkdown.isNextStep("You should focus today"))
    }
}

private struct FailingChatAPIClient: ChatAPIClientProtocol {
    func ask(_ payload: AskRequest) async throws -> AskResponse {
        throw FailingChatAPIError.expectedFailure
    }

    func previewAskContext(_ payload: AskContextPreviewRequest) async throws -> AskContextPreviewResponse {
        throw FailingChatAPIError.expectedFailure
    }

    func listChatSessions() async throws -> [ChatSessionDTO] {
        throw FailingChatAPIError.expectedFailure
    }

    func listMessages(sessionId: UUID) async throws -> [ChatMessageDTO] {
        throw FailingChatAPIError.expectedFailure
    }

    func deleteChatSession(id: UUID) async throws {
        throw FailingChatAPIError.expectedFailure
    }
}

private enum FailingChatAPIError: LocalizedError {
    case expectedFailure

    var errorDescription: String? {
        "Expected chat API failure."
    }
}

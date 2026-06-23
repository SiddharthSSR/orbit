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

    func testUnscopedAskDoesNotSendProjectID() async {
        let client = MockChatAPIClient(sessions: [], messagesBySession: [:])
        let viewModel = makeViewModel(client)
        viewModel.draftQuestion = "What should I focus on?"

        await viewModel.sendQuestion()

        let request = await client.lastAskRequest()
        XCTAssertNotNil(request)
        XCTAssertNil(request?.projectId)
    }

    func testScopedAskSendsSelectedProjectID() async {
        let project = makeScopeProject(name: "Orbit")
        let client = MockChatAPIClient(sessions: [], messagesBySession: [:])
        let viewModel = makeViewModel(client, projectAPIClient: MockProjectAPIClient(projects: [project]))
        await viewModel.loadProjects()
        viewModel.selectProjectScope(project.id)
        viewModel.draftQuestion = "What is the latest?"

        await viewModel.sendQuestion()

        let request = await client.lastAskRequest()
        XCTAssertEqual(request?.projectId, project.id)
        XCTAssertEqual(viewModel.selectedProjectName, "Orbit")
    }

    func testClearingProjectScopeRemovesProjectID() async {
        let project = makeScopeProject(name: "Orbit")
        let client = MockChatAPIClient(sessions: [], messagesBySession: [:])
        let viewModel = makeViewModel(client, projectAPIClient: MockProjectAPIClient(projects: [project]))
        await viewModel.loadProjects()
        viewModel.selectProjectScope(project.id)
        viewModel.clearProjectScope()
        viewModel.draftQuestion = "What is the latest?"

        await viewModel.sendQuestion()

        let request = await client.lastAskRequest()
        XCTAssertNil(request?.projectId)
        XCTAssertNil(viewModel.selectedProjectName)
    }

    func testProjectLoadFailureDoesNotBlockUnscopedAsk() async {
        let client = MockChatAPIClient(sessions: [], messagesBySession: [:])
        let viewModel = makeViewModel(client, projectAPIClient: FailingAskProjectAPIClient())

        await viewModel.loadProjects()
        XCTAssertNotNil(viewModel.projectLoadErrorMessage)
        XCTAssertTrue(viewModel.availableProjects.isEmpty)

        viewModel.draftQuestion = "What should I focus on?"
        await viewModel.sendQuestion()

        XCTAssertNil(viewModel.errorMessage)
        let request = await client.lastAskRequest()
        XCTAssertNotNil(request)
        XCTAssertNil(request?.projectId)
    }

    func testScopedPreviewSendsSelectedProjectID() async {
        let project = makeScopeProject(name: "Orbit")
        let client = MockChatAPIClient(sessions: [], messagesBySession: [:])
        let viewModel = makeViewModel(client, projectAPIClient: MockProjectAPIClient(projects: [project]))
        await viewModel.loadProjects()
        viewModel.selectProjectScope(project.id)
        viewModel.draftQuestion = "What is the latest?"

        await viewModel.previewContext()

        let request = await client.lastPreviewRequest()
        XCTAssertEqual(request?.projectId, project.id)
        XCTAssertEqual(viewModel.previewProjectName, "Orbit")
    }

    func testUnscopedPreviewOmitsProjectID() async {
        let client = MockChatAPIClient(sessions: [], messagesBySession: [:])
        let viewModel = makeViewModel(client)
        viewModel.draftQuestion = "What did I save about AI?"

        await viewModel.previewContext()

        let request = await client.lastPreviewRequest()
        XCTAssertNotNil(request)
        XCTAssertNil(request?.projectId)
        XCTAssertNil(viewModel.previewProjectName)
    }

    func testChangingProjectScopeInvalidatesDisplayedPreview() async {
        let project = makeScopeProject(name: "Orbit")
        let client = MockChatAPIClient(sessions: [], messagesBySession: [:])
        let viewModel = makeViewModel(client, projectAPIClient: MockProjectAPIClient(projects: [project]))
        await viewModel.loadProjects()
        viewModel.draftQuestion = "What did I save about AI?"
        await viewModel.previewContext()
        XCTAssertNotNil(viewModel.contextPreview)

        viewModel.selectProjectScope(project.id)

        XCTAssertNil(viewModel.contextPreview)
        XCTAssertNil(viewModel.previewProjectName)
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

    func testSelectingAndDismissingSuggestedActionUpdatesPreviewState() {
        let viewModel = makeViewModel(MockChatAPIClient(sessions: [], messagesBySession: [:]))
        let action = makeSuggestedAction(type: "review_bills", title: "Review bills")

        viewModel.selectSuggestedAction(action)

        XCTAssertEqual(viewModel.selectedSuggestedAction, action)
        XCTAssertEqual(viewModel.selectedSuggestedActionDraft, SuggestedActionDraft(action: action))
        XCTAssertNotNil(viewModel.editableSuggestedActionDraft)
        viewModel.dismissSuggestedActionPreview()
        XCTAssertNil(viewModel.selectedSuggestedAction)
        XCTAssertNil(viewModel.selectedSuggestedActionDraft)
        XCTAssertNil(viewModel.editableSuggestedActionDraft)
    }

    func testCreateTodoActionMapsToTodoDraft() {
        let draft = SuggestedActionDraft(
            action: makeSuggestedAction(
                type: "create_todo",
                title: "Create a todo",
                subtitle: "Fallback todo title",
                payload: ["draft_title": "Call the dentist"]
            )
        )

        XCTAssertEqual(draft.title, "Create todo draft")
        XCTAssertEqual(draft.actionType, "create_todo")
        XCTAssertEqual(draft.fields, [
            SuggestedActionDraftField(
                label: "Todo title",
                value: "Call the dentist",
                futureEditable: true
            )
        ])
        XCTAssertEqual(draft.confirmationTitle, "Save coming soon")
    }

    func testSaveMemoryActionMapsToMemoryDraft() {
        let draft = SuggestedActionDraft(
            action: makeSuggestedAction(
                type: "save_memory",
                title: "Save to memory",
                subtitle: "Keep this detail in Orbit memory",
                payload: [
                    "memory_text": "I like quiet cafes with plants",
                    "memory_title": "Quiet cafes with plants",
                ]
            )
        )

        XCTAssertEqual(draft.title, "Save memory draft")
        XCTAssertEqual(draft.fields.first?.label, "Memory text")
        XCTAssertEqual(draft.fields.first?.value, "I like quiet cafes with plants")
        XCTAssertEqual(draft.fields.first?.futureEditable, true)
    }

    func testSaveMemoryActionWithoutPayloadFallsBackToSubtitle() {
        let draft = SuggestedActionDraft(
            action: makeSuggestedAction(
                type: "save_memory",
                title: "Save to memory",
                subtitle: "Fallback memory text",
                payload: nil
            )
        )

        XCTAssertEqual(draft.fields.first?.value, "Fallback memory text")
    }

    func testCreateTodoActionWithoutPayloadFallsBackToSubtitle() {
        let draft = SuggestedActionDraft(
            action: makeSuggestedAction(
                type: "create_todo",
                title: "Create a todo",
                subtitle: "Fallback todo title",
                payload: nil
            )
        )

        XCTAssertEqual(draft.fields.first?.value, "Fallback todo title")
    }

    func testReviewBillsActionMapsToReadOnlyReviewDraft() {
        let draft = SuggestedActionDraft(
            action: makeSuggestedAction(
                type: "review_bills",
                title: "Review bills",
                subtitle: "Upcoming payments",
                payload: ["scope": "Overdue and due soon"]
            )
        )

        XCTAssertEqual(draft.title, "Review bills")
        XCTAssertEqual(draft.fields.first?.label, "Scope")
        XCTAssertEqual(draft.fields.first?.value, "Overdue and due soon")
        XCTAssertEqual(draft.fields.first?.futureEditable, false)
        XCTAssertEqual(draft.confirmationTitle, "Confirm coming soon")
    }

    func testUnknownActionMapsToGenericDraft() {
        let draft = SuggestedActionDraft(
            action: makeSuggestedAction(
                type: "future_action",
                title: "Future action",
                subtitle: "Preview future behavior",
                payload: nil
            )
        )

        XCTAssertEqual(draft.title, "Future action")
        XCTAssertEqual(draft.actionType, "future_action")
        XCTAssertEqual(draft.fields.first?.label, "Details")
        XCTAssertEqual(draft.fields.first?.value, "Preview future behavior")
        XCTAssertTrue(draft.primaryText.contains("future confirmation"))
    }

    func testCreateTodoDraftIsInvalidWhenTitleIsEmpty() {
        var draft = makeEditableDraft(type: "create_todo", value: "Call the dentist")

        draft.updateField(id: "Todo title", value: "  \n ")

        XCTAssertFalse(draft.isValid)
        XCTAssertEqual(draft.validationError, "Title is required.")
        XCTAssertEqual(
            draft.validationStatus,
            "Fix required fields before this can be saved in a future MVP."
        )
    }

    func testCreateTodoDraftIsValidWhenTitleIsNonEmpty() {
        let draft = makeEditableDraft(type: "create_todo", value: "Call the dentist")

        XCTAssertTrue(draft.isValid)
        XCTAssertNil(draft.validationError)
        XCTAssertEqual(draft.validationStatus, "Draft looks valid and ready to create a todo.")
    }

    func testSaveMemoryDraftIsInvalidWhenTextIsEmpty() {
        var draft = makeEditableDraft(type: "save_memory", value: "I like quiet cafes")

        draft.updateField(id: "Memory text", value: "   ")

        XCTAssertFalse(draft.isValid)
        XCTAssertEqual(draft.validationError, "Memory text is required.")
    }

    func testSaveMemoryDraftIsValidWhenTextIsNonEmpty() {
        let draft = makeEditableDraft(type: "save_memory", value: "I like quiet cafes")

        XCTAssertTrue(draft.isValid)
        XCTAssertNil(draft.validationError)
    }

    func testReviewBillsDraftIsReadOnlyAndValid() {
        var draft = EditableSuggestedActionDraft(
            source: SuggestedActionDraft(
                action: makeSuggestedAction(
                    type: "review_bills",
                    title: "Review bills",
                    subtitle: "Upcoming payments",
                    payload: nil
                )
            )
        )
        let originalFields = draft.fields

        draft.updateField(id: "Scope", value: "Attempted change")

        XCTAssertTrue(draft.isReadOnly)
        XCTAssertTrue(draft.isValid)
        XCTAssertNil(draft.validationError)
        XCTAssertEqual(draft.fields, originalFields)
    }

    func testLocalDraftEditsDoNotChangeSourceOrMakeAPIRequests() async throws {
        let client = MockChatAPIClient(sessions: [], messagesBySession: [:])
        let viewModel = makeViewModel(client)
        let action = makeSuggestedAction(
            type: "save_memory",
            title: "Save to memory",
            subtitle: "I like quiet cafes",
            payload: nil
        )

        viewModel.selectSuggestedAction(action)
        var editedDraft = try XCTUnwrap(viewModel.editableSuggestedActionDraft)
        editedDraft.updateField(id: "Memory text", value: "Edited only in this sheet")
        viewModel.updateEditableSuggestedActionDraft(editedDraft)

        let askRequest = await client.lastAskRequest()
        let previewRequest = await client.lastPreviewRequest()
        let deletedSessions = await client.deletedSessions()
        XCTAssertEqual(viewModel.editableSuggestedActionDraft?.fields.first?.value, "Edited only in this sheet")
        XCTAssertEqual(viewModel.selectedSuggestedAction, action)
        XCTAssertEqual(viewModel.selectedSuggestedActionDraft?.fields.first?.value, "I like quiet cafes")
        XCTAssertNil(askRequest)
        XCTAssertNil(previewRequest)
        XCTAssertTrue(deletedSessions.isEmpty)
    }

    func testValidSaveMemoryDraftIsExecutable() {
        let draft = makeEditableDraft(type: "save_memory", value: "I like quiet cafes")

        XCTAssertTrue(draft.canExecute)
        XCTAssertEqual(draft.executionButtonTitle, "Save to memory")
        XCTAssertEqual(draft.executionSafetyText, "This will save the draft as a memory.")
    }

    func testInvalidSaveMemoryDraftIsNotExecutable() {
        var draft = makeEditableDraft(type: "save_memory", value: "I like quiet cafes")

        draft.updateField(id: "Memory text", value: "   ")

        XCTAssertFalse(draft.canExecute)
    }

    func testValidCreateTodoDraftIsExecutable() {
        let draft = makeEditableDraft(type: "create_todo", value: "Call the dentist")

        XCTAssertTrue(draft.canExecute)
        XCTAssertEqual(draft.executionButtonTitle, "Create todo")
        XCTAssertEqual(draft.executionSafetyText, "This will create a todo.")
    }

    func testInvalidCreateTodoDraftIsNotExecutable() {
        var draft = makeEditableDraft(type: "create_todo", value: "Call the dentist")

        draft.updateField(id: "Todo title", value: "   ")

        XCTAssertFalse(draft.canExecute)
    }

    func testReviewBillsDraftIsExecutableAsNavigation() {
        let bills = EditableSuggestedActionDraft(
            source: SuggestedActionDraft(
                action: makeSuggestedAction(type: "review_bills", title: "Review bills", subtitle: "Bills", payload: nil)
            )
        )

        XCTAssertTrue(bills.canExecute)
        XCTAssertTrue(bills.isNavigationAction)
        XCTAssertEqual(bills.executionButtonTitle, "Review bills")
        XCTAssertEqual(bills.executionSafetyText, "This will open Bills. Nothing will be changed.")
        // Still read-only — navigation never mutates the draft fields.
        XCTAssertTrue(bills.isReadOnly)
    }

    func testUnknownActionRemainsDisabled() {
        let unknown = EditableSuggestedActionDraft(
            source: SuggestedActionDraft(
                action: makeSuggestedAction(type: "future_action", title: "Future", subtitle: "x", payload: nil)
            )
        )

        XCTAssertFalse(unknown.canExecute)
        XCTAssertFalse(unknown.isNavigationAction)
        XCTAssertEqual(unknown.executionButtonTitle, "Coming soon")
        XCTAssertNil(unknown.executionSafetyText)
    }

    func testSaveMemorySuccessRecordsStatusForSelectedMessageAction() async {
        let viewModel = makeViewModel(MockChatAPIClient(sessions: [], messagesBySession: [:]))
        let message = makeMessage(sessionId: UUID(), role: "assistant")
        let action = makeSuggestedAction(
            type: "save_memory",
            title: "Save to memory",
            subtitle: "I like quiet cafes",
            payload: nil
        )
        viewModel.selectSuggestedAction(action, messageID: message.id)

        await viewModel.executeSelectedSuggestedActionDraft()

        XCTAssertEqual(
            viewModel.suggestedActionExecutionStatus(for: message, action: action),
            .completed(displayText: "Saved to memory")
        )
    }

    func testCreateTodoSuccessRecordsStatusForSelectedMessageAction() async {
        let viewModel = makeViewModel(MockChatAPIClient(sessions: [], messagesBySession: [:]))
        let message = makeMessage(sessionId: UUID(), role: "assistant")
        let action = makeSuggestedAction(
            type: "create_todo",
            title: "Create a todo",
            subtitle: "Call the dentist",
            payload: nil
        )
        viewModel.selectSuggestedAction(action, messageID: message.id)

        await viewModel.executeSelectedSuggestedActionDraft()

        XCTAssertEqual(
            viewModel.suggestedActionExecutionStatus(for: message, action: action),
            .completed(displayText: "Todo created")
        )
    }

    func testReviewBillsSuccessRecordsStatusOnlyForSelectedMessageAction() async {
        let viewModel = makeViewModel(MockChatAPIClient(sessions: [], messagesBySession: [:]))
        let message = makeMessage(sessionId: UUID(), role: "assistant")
        let otherMessage = makeMessage(sessionId: message.sessionId, role: "assistant")
        let action = makeSuggestedAction(
            type: "review_bills",
            title: "Review bills",
            subtitle: "Upcoming",
            payload: nil
        )
        let otherAction = SuggestedActionDTO(
            id: "review-bills-other",
            type: action.type,
            title: action.title,
            subtitle: action.subtitle,
            payload: action.payload
        )
        viewModel.selectSuggestedAction(action, messageID: message.id)

        await viewModel.executeSelectedSuggestedActionDraft()

        XCTAssertEqual(
            viewModel.suggestedActionExecutionStatus(for: message, action: action),
            .completed(displayText: "Opened Bills")
        )
        XCTAssertNil(viewModel.suggestedActionExecutionStatus(for: message, action: otherAction))
        XCTAssertNil(viewModel.suggestedActionExecutionStatus(for: otherMessage, action: action))
    }

    func testSaveMemoryExecutionNavigatesToInboxAndReloadsCreatedMemory() async throws {
        let center = NotificationCenter()
        let memoryClient = MockMemoryAPIClient(memoryItems: [])
        let askViewModel = makeViewModel(
            MockChatAPIClient(sessions: [], messagesBySession: [:]),
            memoryClient: memoryClient,
            notificationCenter: center
        )
        let inboxViewModel = MemoryListViewModel(
            apiClient: memoryClient,
            notificationCenter: center
        )
        let navigation = AppNavigationModel(selectedTab: .ask)
        let refreshEvent = XCTNSNotificationExpectation(
            name: .orbitMemoryDidChange,
            object: nil,
            notificationCenter: center
        )
        askViewModel.selectSuggestedAction(
            makeSuggestedAction(type: "save_memory", title: "Save to memory", subtitle: "Draft", payload: nil)
        )
        var draft = try XCTUnwrap(askViewModel.editableSuggestedActionDraft)
        draft.updateField(id: "Memory text", value: "I like quiet cafes")
        askViewModel.updateEditableSuggestedActionDraft(draft)

        await askViewModel.executeSelectedSuggestedActionDraft()
        await fulfillment(of: [refreshEvent], timeout: 0.5)

        XCTAssertEqual(askViewModel.pendingTabNavigation, .inbox)
        guard case let .memory(createdMemoryID)? = askViewModel.pendingHighlight else {
            return XCTFail("Expected a memory highlight target")
        }
        applyPendingNavigation(from: askViewModel, to: navigation)
        await inboxViewModel.loadMemory(showsLoading: false)

        let requests = await memoryClient.recordedCreateRequests()
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(navigation.selectedTab, .inbox)
        XCTAssertEqual(navigation.pendingHighlight, .memory(createdMemoryID))
        XCTAssertNil(askViewModel.pendingTabNavigation)
        XCTAssertNil(askViewModel.pendingHighlight)
        XCTAssertEqual(inboxViewModel.memoryItems.map(\.body), ["I like quiet cafes"])
        XCTAssertTrue(inboxViewModel.memoryItems.contains { $0.id == createdMemoryID })
        XCTAssertTrue(navigation.consumeHighlight(.memory(createdMemoryID)))
        XCTAssertNil(navigation.pendingHighlight)
        XCTAssertNil(inboxViewModel.errorMessage)
    }

    func testCreateTodoExecutionNavigatesToTodayAndReloadsCreatedTodo() async throws {
        let center = NotificationCenter()
        let todoClient = MockTodoAPIClient(todos: [])
        let askViewModel = makeViewModel(
            MockChatAPIClient(sessions: [], messagesBySession: [:]),
            todoClient: todoClient,
            notificationCenter: center
        )
        let todayViewModel = TodayDashboardViewModel(
            todoAPIClient: todoClient,
            billAPIClient: MockBillAPIClient(bills: []),
            memoryAPIClient: MockMemoryAPIClient(memoryItems: []),
            moodAPIClient: MockMoodAPIClient(moods: []),
            notificationCenter: center
        )
        let navigation = AppNavigationModel(selectedTab: .ask)
        let refreshEvent = XCTNSNotificationExpectation(
            name: .orbitTodoDidChange,
            object: nil,
            notificationCenter: center
        )
        askViewModel.selectSuggestedAction(
            makeSuggestedAction(type: "create_todo", title: "Create a todo", subtitle: "Draft", payload: nil)
        )
        var draft = try XCTUnwrap(askViewModel.editableSuggestedActionDraft)
        draft.updateField(id: "Todo title", value: "Call the dentist")
        askViewModel.updateEditableSuggestedActionDraft(draft)

        await askViewModel.executeSelectedSuggestedActionDraft()
        await fulfillment(of: [refreshEvent], timeout: 0.5)

        XCTAssertEqual(askViewModel.pendingTabNavigation, .today)
        guard case let .todo(createdTodoID)? = askViewModel.pendingHighlight else {
            return XCTFail("Expected a todo highlight target")
        }
        applyPendingNavigation(from: askViewModel, to: navigation)
        await todayViewModel.loadDashboard(showsLoading: false)

        let requests = await todoClient.recordedCreateRequests()
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(navigation.selectedTab, .today)
        XCTAssertEqual(navigation.pendingHighlight, .todo(createdTodoID))
        XCTAssertNil(askViewModel.pendingTabNavigation)
        XCTAssertNil(askViewModel.pendingHighlight)
        XCTAssertEqual(todayViewModel.openTodos.map(\.title), ["Call the dentist"])
        XCTAssertTrue(todayViewModel.openTodos.contains { $0.id == createdTodoID })
        XCTAssertTrue(navigation.consumeHighlight(.todo(createdTodoID)))
        XCTAssertNil(navigation.pendingHighlight)
        XCTAssertNil(todayViewModel.errorMessage)
    }

    func testReviewBillsExecutionSelectsBillsWithoutCreatingRecords() async {
        let memoryClient = MockMemoryAPIClient(memoryItems: [])
        let todoClient = MockTodoAPIClient(todos: [])
        let askViewModel = makeViewModel(
            MockChatAPIClient(sessions: [], messagesBySession: [:]),
            memoryClient: memoryClient,
            todoClient: todoClient
        )
        let navigation = AppNavigationModel(selectedTab: .ask)
        askViewModel.selectSuggestedAction(
            makeSuggestedAction(type: "review_bills", title: "Review bills", subtitle: "Upcoming", payload: nil)
        )

        await askViewModel.executeSelectedSuggestedActionDraft()

        XCTAssertEqual(askViewModel.pendingTabNavigation, .bills)
        XCTAssertNil(askViewModel.pendingHighlight)
        applyPendingNavigation(from: askViewModel, to: navigation)

        let memoryRequests = await memoryClient.recordedCreateRequests()
        let todoRequests = await todoClient.recordedCreateRequests()
        XCTAssertTrue(memoryRequests.isEmpty)
        XCTAssertTrue(todoRequests.isEmpty)
        XCTAssertEqual(navigation.selectedTab, .bills)
        XCTAssertNil(navigation.pendingHighlight)
        XCTAssertNil(askViewModel.pendingTabNavigation)
    }

    func testExecuteSaveMemoryCallsCreateOnceWithTrimmedTextAndClearsDraft() async throws {
        let memoryClient = MockMemoryAPIClient(memoryItems: [])
        let viewModel = makeViewModel(
            MockChatAPIClient(sessions: [], messagesBySession: [:]),
            memoryClient: memoryClient
        )
        viewModel.selectSuggestedAction(
            makeSuggestedAction(type: "save_memory", title: "Save to memory", subtitle: "Draft text", payload: nil)
        )
        var draft = try XCTUnwrap(viewModel.editableSuggestedActionDraft)
        draft.updateField(id: "Memory text", value: "  I like quiet cafes  ")
        viewModel.updateEditableSuggestedActionDraft(draft)

        await viewModel.executeSelectedSuggestedActionDraft()

        let requests = await memoryClient.recordedCreateRequests()
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.body, "I like quiet cafes")
        XCTAssertEqual(requests.first?.kind, "note")
        XCTAssertNil(requests.first?.projectId)
        XCTAssertFalse(requests.first?.title.isEmpty ?? true)
        XCTAssertEqual(viewModel.suggestedActionSuccessMessage, "Saved to memory")
        XCTAssertEqual(viewModel.pendingTabNavigation, .inbox)
        guard case .memory? = viewModel.pendingHighlight else {
            return XCTFail("Expected a memory highlight target")
        }
        XCTAssertNil(viewModel.selectedSuggestedAction)
        XCTAssertNil(viewModel.editableSuggestedActionDraft)
        XCTAssertNil(viewModel.suggestedActionErrorMessage)
        XCTAssertFalse(viewModel.isExecutingSuggestedAction)
    }

    func testExecuteSaveMemoryFailureKeepsDraftAndShowsError() async throws {
        let message = makeMessage(sessionId: UUID(), role: "assistant")
        let action = makeSuggestedAction(
            type: "save_memory",
            title: "Save to memory",
            subtitle: "I like quiet cafes",
            payload: nil
        )
        let viewModel = makeViewModel(
            MockChatAPIClient(sessions: [], messagesBySession: [:]),
            memoryClient: FailingMemoryAPIClient()
        )
        viewModel.selectSuggestedAction(action, messageID: message.id)

        await viewModel.executeSelectedSuggestedActionDraft()

        XCTAssertNotNil(viewModel.editableSuggestedActionDraft)
        XCTAssertNotNil(viewModel.selectedSuggestedAction)
        XCTAssertNil(viewModel.suggestedActionSuccessMessage)
        XCTAssertEqual(viewModel.suggestedActionErrorMessage, "Expected memory API failure.")
        XCTAssertNil(viewModel.pendingTabNavigation)
        XCTAssertNil(viewModel.pendingHighlight)
        XCTAssertNil(viewModel.suggestedActionExecutionStatus(for: message, action: action))
        XCTAssertFalse(viewModel.isExecutingSuggestedAction)
    }

    func testExecuteCreateTodoCallsTodoCreateOnceWithTrimmedTitleAndClearsDraft() async throws {
        let memoryClient = MockMemoryAPIClient(memoryItems: [])
        let todoClient = MockTodoAPIClient(todos: [])
        let viewModel = makeViewModel(
            MockChatAPIClient(sessions: [], messagesBySession: [:]),
            memoryClient: memoryClient,
            todoClient: todoClient
        )
        viewModel.selectSuggestedAction(
            makeSuggestedAction(type: "create_todo", title: "Create a todo", subtitle: "Draft title", payload: nil)
        )
        var draft = try XCTUnwrap(viewModel.editableSuggestedActionDraft)
        draft.updateField(id: "Todo title", value: "  Call the dentist  ")
        viewModel.updateEditableSuggestedActionDraft(draft)

        await viewModel.executeSelectedSuggestedActionDraft()

        let todoRequests = await todoClient.recordedCreateRequests()
        let memoryRequests = await memoryClient.recordedCreateRequests()
        XCTAssertEqual(todoRequests.count, 1)
        XCTAssertEqual(todoRequests.first?.title, "Call the dentist")
        XCTAssertTrue(memoryRequests.isEmpty, "create_todo must not create a memory")
        XCTAssertEqual(viewModel.suggestedActionSuccessMessage, "Todo created")
        XCTAssertEqual(viewModel.pendingTabNavigation, .today)
        guard case .todo? = viewModel.pendingHighlight else {
            return XCTFail("Expected a todo highlight target")
        }
        XCTAssertNil(viewModel.selectedSuggestedAction)
        XCTAssertNil(viewModel.editableSuggestedActionDraft)
        XCTAssertNil(viewModel.suggestedActionErrorMessage)
        XCTAssertFalse(viewModel.isExecutingSuggestedAction)
    }

    func testExecuteCreateTodoFailureKeepsDraftAndShowsError() async {
        let message = makeMessage(sessionId: UUID(), role: "assistant")
        let action = makeSuggestedAction(
            type: "create_todo",
            title: "Create a todo",
            subtitle: "Call the dentist",
            payload: nil
        )
        let viewModel = makeViewModel(
            MockChatAPIClient(sessions: [], messagesBySession: [:]),
            todoClient: FailingTodoAPIClient()
        )
        viewModel.selectSuggestedAction(action, messageID: message.id)

        await viewModel.executeSelectedSuggestedActionDraft()

        XCTAssertNotNil(viewModel.editableSuggestedActionDraft)
        XCTAssertNotNil(viewModel.selectedSuggestedAction)
        XCTAssertNil(viewModel.suggestedActionSuccessMessage)
        XCTAssertEqual(viewModel.suggestedActionErrorMessage, "Expected todo API failure.")
        XCTAssertNil(viewModel.pendingTabNavigation)
        XCTAssertNil(viewModel.pendingHighlight)
        XCTAssertNil(viewModel.suggestedActionExecutionStatus(for: message, action: action))
        XCTAssertFalse(viewModel.isExecutingSuggestedAction)
    }

    func testExecuteDoesNotCreateTodoForInvalidCreateTodoDraft() async throws {
        let todoClient = MockTodoAPIClient(todos: [])
        let message = makeMessage(sessionId: UUID(), role: "assistant")
        let action = makeSuggestedAction(
            type: "create_todo",
            title: "Create a todo",
            subtitle: "Draft",
            payload: nil
        )
        let viewModel = makeViewModel(
            MockChatAPIClient(sessions: [], messagesBySession: [:]),
            todoClient: todoClient
        )
        viewModel.selectSuggestedAction(action, messageID: message.id)
        var draft = try XCTUnwrap(viewModel.editableSuggestedActionDraft)
        draft.updateField(id: "Todo title", value: "   ")
        viewModel.updateEditableSuggestedActionDraft(draft)

        await viewModel.executeSelectedSuggestedActionDraft()

        let requests = await todoClient.recordedCreateRequests()
        XCTAssertTrue(requests.isEmpty)
        XCTAssertNotNil(viewModel.editableSuggestedActionDraft)
        XCTAssertNil(viewModel.pendingTabNavigation)
        XCTAssertNil(viewModel.pendingHighlight)
        XCTAssertNil(viewModel.suggestedActionExecutionStatus(for: message, action: action))
    }

    func testRepeatedExecuteDoesNotCreateDuplicateTodo() async {
        let todoClient = MockTodoAPIClient(todos: [])
        let viewModel = makeViewModel(
            MockChatAPIClient(sessions: [], messagesBySession: [:]),
            todoClient: todoClient
        )
        viewModel.selectSuggestedAction(
            makeSuggestedAction(type: "create_todo", title: "Create a todo", subtitle: "Call the dentist", payload: nil)
        )

        await viewModel.executeSelectedSuggestedActionDraft()
        // Second call has no draft (cleared on success), so it must be a no-op.
        await viewModel.executeSelectedSuggestedActionDraft()

        let requests = await todoClient.recordedCreateRequests()
        XCTAssertEqual(requests.count, 1)
    }

    func testExecuteReviewBillsNavigatesToBillsWithoutMutating() async {
        let memoryClient = MockMemoryAPIClient(memoryItems: [])
        let todoClient = MockTodoAPIClient(todos: [])
        let viewModel = makeViewModel(
            MockChatAPIClient(sessions: [], messagesBySession: [:]),
            memoryClient: memoryClient,
            todoClient: todoClient
        )
        viewModel.selectSuggestedAction(
            makeSuggestedAction(type: "review_bills", title: "Review bills", subtitle: "Upcoming", payload: nil)
        )

        await viewModel.executeSelectedSuggestedActionDraft()

        // Navigation intent set, no record mutations, draft cleared.
        XCTAssertEqual(viewModel.pendingTabNavigation, .bills)
        XCTAssertNil(viewModel.pendingHighlight)
        let todoRequests = await todoClient.recordedCreateRequests()
        let memoryRequests = await memoryClient.recordedCreateRequests()
        XCTAssertTrue(todoRequests.isEmpty)
        XCTAssertTrue(memoryRequests.isEmpty)
        XCTAssertNil(viewModel.suggestedActionSuccessMessage)
        XCTAssertNil(viewModel.selectedSuggestedAction)
        XCTAssertNil(viewModel.editableSuggestedActionDraft)
    }

    func testReviewBillsExecutionEmitsNoRefreshEvents() async {
        let center = NotificationCenter()
        let viewModel = makeViewModel(
            MockChatAPIClient(sessions: [], messagesBySession: [:]),
            notificationCenter: center
        )
        viewModel.selectSuggestedAction(
            makeSuggestedAction(type: "review_bills", title: "Review bills", subtitle: "Upcoming", payload: nil)
        )
        let billsEvent = XCTNSNotificationExpectation(name: .orbitBillsDidChange, object: nil, notificationCenter: center)
        billsEvent.isInverted = true
        let memoryEvent = XCTNSNotificationExpectation(name: .orbitMemoryDidChange, object: nil, notificationCenter: center)
        memoryEvent.isInverted = true
        let todoEvent = XCTNSNotificationExpectation(name: .orbitTodoDidChange, object: nil, notificationCenter: center)
        todoEvent.isInverted = true

        await viewModel.executeSelectedSuggestedActionDraft()

        await fulfillment(of: [billsEvent, memoryEvent, todoEvent], timeout: 0.3)
    }

    func testClearPendingTabNavigationResetsIntent() async {
        let viewModel = makeViewModel(MockChatAPIClient(sessions: [], messagesBySession: [:]))
        viewModel.selectSuggestedAction(
            makeSuggestedAction(type: "review_bills", title: "Review bills", subtitle: "Upcoming", payload: nil)
        )
        await viewModel.executeSelectedSuggestedActionDraft()
        XCTAssertEqual(viewModel.pendingTabNavigation, .bills)

        viewModel.clearPendingTabNavigation()

        XCTAssertNil(viewModel.pendingTabNavigation)
    }

    func testAppNavigationHighlightCanBeCleared() {
        let todoID = UUID()
        let navigation = AppNavigationModel(selectedTab: .ask)
        navigation.navigate(to: .today, highlighting: .todo(todoID))

        XCTAssertEqual(navigation.selectedTab, .today)
        XCTAssertEqual(navigation.pendingHighlight, .todo(todoID))

        navigation.clearHighlight()

        XCTAssertNil(navigation.pendingHighlight)
        XCTAssertFalse(navigation.consumeHighlight(.todo(todoID)))
    }

    func testStartNewSessionClearsSuggestedActionExecutionStatuses() async {
        let viewModel = makeViewModel(MockChatAPIClient(sessions: [], messagesBySession: [:]))
        let message = makeMessage(sessionId: UUID(), role: "assistant")
        let action = makeSuggestedAction(
            type: "review_bills",
            title: "Review bills",
            subtitle: "Upcoming",
            payload: nil
        )
        viewModel.selectSuggestedAction(action, messageID: message.id)
        await viewModel.executeSelectedSuggestedActionDraft()
        XCTAssertFalse(viewModel.suggestedActionExecutionStatuses.isEmpty)

        viewModel.startNewSession()

        XCTAssertTrue(viewModel.suggestedActionExecutionStatuses.isEmpty)
    }

    func testSessionSwitchClearsSuggestedActionExecutionStatuses() async {
        let session = makeSession(title: "Other chat")
        let viewModel = makeViewModel(
            MockChatAPIClient(sessions: [session], messagesBySession: [session.id: []])
        )
        let message = makeMessage(sessionId: UUID(), role: "assistant")
        let action = makeSuggestedAction(
            type: "review_bills",
            title: "Review bills",
            subtitle: "Upcoming",
            payload: nil
        )
        viewModel.selectSuggestedAction(action, messageID: message.id)
        await viewModel.executeSelectedSuggestedActionDraft()
        XCTAssertFalse(viewModel.suggestedActionExecutionStatuses.isEmpty)

        await viewModel.selectSession(session)

        XCTAssertTrue(viewModel.suggestedActionExecutionStatuses.isEmpty)
    }

    func testDeletingSelectedSessionClearsSuggestedActionExecutionStatuses() async {
        let session = makeSession(title: "Active")
        let client = MockChatAPIClient(
            sessions: [session],
            messagesBySession: [session.id: [makeMessage(sessionId: session.id)]]
        )
        let viewModel = makeViewModel(client)
        await viewModel.selectSession(session)
        let message = makeMessage(sessionId: session.id, role: "assistant")
        let action = makeSuggestedAction(
            type: "review_bills",
            title: "Review bills",
            subtitle: "Upcoming",
            payload: nil
        )
        viewModel.selectSuggestedAction(action, messageID: message.id)
        await viewModel.executeSelectedSuggestedActionDraft()
        XCTAssertFalse(viewModel.suggestedActionExecutionStatuses.isEmpty)

        await viewModel.deleteSession(session)

        XCTAssertTrue(viewModel.suggestedActionExecutionStatuses.isEmpty)
    }

    func testUnknownActionExecutionDoesNotNavigate() async {
        let viewModel = makeViewModel(MockChatAPIClient(sessions: [], messagesBySession: [:]))
        let message = makeMessage(sessionId: UUID(), role: "assistant")
        let action = makeSuggestedAction(
            type: "future_action",
            title: "Future",
            subtitle: "x",
            payload: nil
        )
        viewModel.selectSuggestedAction(action, messageID: message.id)

        await viewModel.executeSelectedSuggestedActionDraft()

        XCTAssertNil(viewModel.pendingTabNavigation)
        XCTAssertNil(viewModel.pendingHighlight)
        XCTAssertNil(viewModel.suggestedActionSuccessMessage)
        XCTAssertNil(viewModel.suggestedActionExecutionStatus(for: message, action: action))
        // Non-executable action leaves the draft preview untouched.
        XCTAssertNotNil(viewModel.editableSuggestedActionDraft)
    }

    func testExecuteSaveMemorySuccessEmitsMemoryRefreshEvent() async {
        let center = NotificationCenter()
        let viewModel = makeViewModel(
            MockChatAPIClient(sessions: [], messagesBySession: [:]),
            notificationCenter: center
        )
        viewModel.selectSuggestedAction(
            makeSuggestedAction(type: "save_memory", title: "Save to memory", subtitle: "I like quiet cafes", payload: nil)
        )
        let memoryEvent = XCTNSNotificationExpectation(name: .orbitMemoryDidChange, object: nil, notificationCenter: center)
        let todoEvent = XCTNSNotificationExpectation(name: .orbitTodoDidChange, object: nil, notificationCenter: center)
        todoEvent.isInverted = true

        await viewModel.executeSelectedSuggestedActionDraft()

        await fulfillment(of: [memoryEvent, todoEvent], timeout: 0.5)
    }

    func testExecuteCreateTodoSuccessEmitsTodoRefreshEvent() async {
        let center = NotificationCenter()
        let viewModel = makeViewModel(
            MockChatAPIClient(sessions: [], messagesBySession: [:]),
            notificationCenter: center
        )
        viewModel.selectSuggestedAction(
            makeSuggestedAction(type: "create_todo", title: "Create a todo", subtitle: "Call the dentist", payload: nil)
        )
        let todoEvent = XCTNSNotificationExpectation(name: .orbitTodoDidChange, object: nil, notificationCenter: center)
        let memoryEvent = XCTNSNotificationExpectation(name: .orbitMemoryDidChange, object: nil, notificationCenter: center)
        memoryEvent.isInverted = true

        await viewModel.executeSelectedSuggestedActionDraft()

        await fulfillment(of: [todoEvent, memoryEvent], timeout: 0.5)
    }

    func testFailedSaveMemoryDoesNotEmitRefreshEvent() async {
        let center = NotificationCenter()
        let viewModel = makeViewModel(
            MockChatAPIClient(sessions: [], messagesBySession: [:]),
            memoryClient: FailingMemoryAPIClient(),
            notificationCenter: center
        )
        viewModel.selectSuggestedAction(
            makeSuggestedAction(type: "save_memory", title: "Save to memory", subtitle: "I like quiet cafes", payload: nil)
        )
        let memoryEvent = XCTNSNotificationExpectation(name: .orbitMemoryDidChange, object: nil, notificationCenter: center)
        memoryEvent.isInverted = true

        await viewModel.executeSelectedSuggestedActionDraft()

        await fulfillment(of: [memoryEvent], timeout: 0.3)
    }

    func testFailedCreateTodoDoesNotEmitRefreshEvent() async {
        let center = NotificationCenter()
        let viewModel = makeViewModel(
            MockChatAPIClient(sessions: [], messagesBySession: [:]),
            todoClient: FailingTodoAPIClient(),
            notificationCenter: center
        )
        viewModel.selectSuggestedAction(
            makeSuggestedAction(type: "create_todo", title: "Create a todo", subtitle: "Call the dentist", payload: nil)
        )
        let todoEvent = XCTNSNotificationExpectation(name: .orbitTodoDidChange, object: nil, notificationCenter: center)
        todoEvent.isInverted = true

        await viewModel.executeSelectedSuggestedActionDraft()

        await fulfillment(of: [todoEvent], timeout: 0.3)
    }

    func testExecuteDoesNotCreateMemoryForInvalidSaveMemoryDraft() async throws {
        let memoryClient = MockMemoryAPIClient(memoryItems: [])
        let message = makeMessage(sessionId: UUID(), role: "assistant")
        let action = makeSuggestedAction(
            type: "save_memory",
            title: "Save to memory",
            subtitle: "Draft",
            payload: nil
        )
        let viewModel = makeViewModel(
            MockChatAPIClient(sessions: [], messagesBySession: [:]),
            memoryClient: memoryClient
        )
        viewModel.selectSuggestedAction(action, messageID: message.id)
        var draft = try XCTUnwrap(viewModel.editableSuggestedActionDraft)
        draft.updateField(id: "Memory text", value: "   ")
        viewModel.updateEditableSuggestedActionDraft(draft)

        await viewModel.executeSelectedSuggestedActionDraft()

        let requests = await memoryClient.recordedCreateRequests()
        XCTAssertTrue(requests.isEmpty)
        XCTAssertNil(viewModel.pendingTabNavigation)
        XCTAssertNil(viewModel.pendingHighlight)
        XCTAssertNil(viewModel.suggestedActionExecutionStatus(for: message, action: action))
    }

    func testRepeatedExecuteDoesNotCreateDuplicateMemory() async throws {
        let memoryClient = MockMemoryAPIClient(memoryItems: [])
        let viewModel = makeViewModel(
            MockChatAPIClient(sessions: [], messagesBySession: [:]),
            memoryClient: memoryClient
        )
        viewModel.selectSuggestedAction(
            makeSuggestedAction(type: "save_memory", title: "Save to memory", subtitle: "I like quiet cafes", payload: nil)
        )

        await viewModel.executeSelectedSuggestedActionDraft()
        // Second call has no draft (cleared on success), so it must be a no-op.
        await viewModel.executeSelectedSuggestedActionDraft()

        let requests = await memoryClient.recordedCreateRequests()
        XCTAssertEqual(requests.count, 1)
    }

    func testUnknownSuggestedActionUsesGenericPreviewCopy() {
        let action = makeSuggestedAction(type: "future_action", title: "Future action")

        XCTAssertEqual(action.typeLabel, "Suggested action")
        XCTAssertEqual(action.previewTitle, "Future action")
        XCTAssertTrue(action.previewDescription.contains("suggested action"))
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

    func testSelectSessionClearsSuggestedActionDraft() async {
        let session = makeSession(title: "Existing")
        let viewModel = makeViewModel(
            MockChatAPIClient(sessions: [session], messagesBySession: [session.id: []])
        )
        viewModel.selectSuggestedAction(makeSuggestedAction())

        await viewModel.selectSession(session)

        XCTAssertNil(viewModel.selectedSuggestedAction)
        XCTAssertNil(viewModel.selectedSuggestedActionDraft)
        XCTAssertNil(viewModel.editableSuggestedActionDraft)
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
        viewModel.selectSuggestedAction(makeSuggestedAction())
        viewModel.startNewSession()

        XCTAssertNil(viewModel.selectedSession)
        XCTAssertTrue(viewModel.messages.isEmpty)
        XCTAssertEqual(viewModel.draftQuestion, "")
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertNil(viewModel.contextPreview)
        XCTAssertNil(viewModel.latestRetrievalDiagnostics)
        XCTAssertTrue(viewModel.answerContextSummaries.isEmpty)
        XCTAssertTrue(viewModel.answerSuggestedActions.isEmpty)
        XCTAssertNil(viewModel.selectedSuggestedAction)
        XCTAssertNil(viewModel.editableSuggestedActionDraft)
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
        viewModel.selectSuggestedAction(makeSuggestedAction())
        XCTAssertFalse(viewModel.messages.isEmpty)

        await viewModel.deleteSession(session)

        XCTAssertNil(viewModel.selectedSession)
        XCTAssertTrue(viewModel.messages.isEmpty)
        XCTAssertTrue(viewModel.sessions.isEmpty)
        XCTAssertNil(viewModel.selectedSuggestedAction)
        XCTAssertNil(viewModel.selectedSuggestedActionDraft)
        XCTAssertNil(viewModel.editableSuggestedActionDraft)
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
        viewModel.selectSuggestedAction(makeSuggestedAction())

        await viewModel.clearCurrentSession()

        let deleted = await client.deletedSessions()
        XCTAssertEqual(deleted, [session.id])
        XCTAssertNil(viewModel.selectedSession)
        XCTAssertTrue(viewModel.messages.isEmpty)
        XCTAssertNil(viewModel.selectedSuggestedAction)
        XCTAssertNil(viewModel.editableSuggestedActionDraft)
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
        memoryClient: (any MemoryAPIClientProtocol)? = nil,
        todoClient: (any TodoAPIClientProtocol)? = nil,
        projectAPIClient: (any ProjectAPIClientProtocol)? = nil,
        notificationCenter: NotificationCenter? = nil,
        defaults: UserDefaults? = nil
    ) -> AskViewModel {
        AskViewModel(
            apiClient: apiClient,
            memoryClient: memoryClient ?? MockMemoryAPIClient(memoryItems: []),
            todoClient: todoClient ?? MockTodoAPIClient(todos: []),
            projectAPIClient: projectAPIClient ?? MockProjectAPIClient(projects: []),
            notificationCenter: notificationCenter ?? NotificationCenter(),
            preferences: AskRetrievalPreferences(defaults: defaults ?? makeIsolatedDefaults())
        )
    }

    private func makeScopeProject(name: String) -> ProjectDTO {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        return ProjectDTO(
            id: UUID(),
            name: name,
            description: nil,
            status: "active",
            area: nil,
            tags: [],
            createdAt: now,
            updatedAt: now
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

    private func makeSuggestedAction(
        type: String = "create_todo",
        title: String = "Create a todo",
        subtitle: String? = "Preview details",
        payload: [String: String]? = ["draft_title": "Follow up"]
    ) -> SuggestedActionDTO {
        SuggestedActionDTO(
            id: type,
            type: type,
            title: title,
            subtitle: subtitle,
            payload: payload
        )
    }

    private func makeEditableDraft(type: String, value: String) -> EditableSuggestedActionDraft {
        let action: SuggestedActionDTO
        switch type {
        case "save_memory":
            action = makeSuggestedAction(
                type: type,
                title: "Save to memory",
                subtitle: value,
                payload: nil
            )
        default:
            action = makeSuggestedAction(
                type: type,
                title: "Create a todo",
                subtitle: value,
                payload: nil
            )
        }
        return EditableSuggestedActionDraft(source: SuggestedActionDraft(action: action))
    }

    private func applyPendingNavigation(
        from viewModel: AskViewModel,
        to navigation: AppNavigationModel
    ) {
        guard let tab = viewModel.pendingTabNavigation else { return }
        navigation.navigate(to: tab, highlighting: viewModel.pendingHighlight)
        viewModel.clearPendingTabNavigation()
        viewModel.clearPendingHighlight()
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

private struct FailingMemoryAPIClient: MemoryAPIClientProtocol {
    func listMemory(includeArchived: Bool, kind: String?, tag: String?, projectId: UUID?) async throws -> [MemoryDTO] {
        throw FailingMemoryAPIError.expectedFailure
    }

    func createMemory(_ payload: MemoryCreateRequest) async throws -> MemoryDTO {
        throw FailingMemoryAPIError.expectedFailure
    }

    func updateMemory(id: UUID, payload: MemoryUpdateRequest) async throws -> MemoryDTO {
        throw FailingMemoryAPIError.expectedFailure
    }

    func updateMemoryProject(id: UUID, payload: MemoryProjectLinkRequest) async throws -> MemoryDTO {
        throw FailingMemoryAPIError.expectedFailure
    }

    func deleteMemory(id: UUID) async throws {
        throw FailingMemoryAPIError.expectedFailure
    }
}

private enum FailingMemoryAPIError: LocalizedError {
    case expectedFailure

    var errorDescription: String? {
        "Expected memory API failure."
    }
}

private struct FailingTodoAPIClient: TodoAPIClientProtocol {
    func listTodos(projectId: UUID?) async throws -> [TodoDTO] {
        throw FailingTodoAPIError.expectedFailure
    }

    func createTodo(_ payload: TodoCreateRequest) async throws -> TodoDTO {
        throw FailingTodoAPIError.expectedFailure
    }

    func updateTodo(id: UUID, payload: TodoUpdateRequest) async throws -> TodoDTO {
        throw FailingTodoAPIError.expectedFailure
    }

    func deleteTodo(id: UUID) async throws {
        throw FailingTodoAPIError.expectedFailure
    }
}

private enum FailingTodoAPIError: LocalizedError {
    case expectedFailure

    var errorDescription: String? {
        "Expected todo API failure."
    }
}

private struct FailingAskProjectAPIClient: ProjectAPIClientProtocol {
    func listProjects(includeArchived: Bool, status: String?, area: String?, tag: String?) async throws -> [ProjectDTO] {
        throw FailingAskProjectAPIError.expectedFailure
    }

    func createProject(_ payload: ProjectCreateRequest) async throws -> ProjectDTO {
        throw FailingAskProjectAPIError.expectedFailure
    }

    func updateProject(id: UUID, payload: ProjectUpdateRequest) async throws -> ProjectDTO {
        throw FailingAskProjectAPIError.expectedFailure
    }

    func deleteProject(id: UUID) async throws {
        throw FailingAskProjectAPIError.expectedFailure
    }
}

private enum FailingAskProjectAPIError: LocalizedError {
    case expectedFailure

    var errorDescription: String? {
        "Expected project API failure."
    }
}

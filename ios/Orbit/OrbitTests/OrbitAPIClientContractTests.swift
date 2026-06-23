import XCTest
@testable import Orbit

final class AppLaunchConfigurationTests: XCTestCase {
    func testUITestArgumentEnablesMockMode() {
        let configuration = AppLaunchConfiguration(
            arguments: ["Orbit", "--orbit-ui-tests"],
            environment: [:]
        )

        XCTAssertEqual(configuration.mode, .mock)
    }

    func testMockEnvironmentVariableEnablesMockMode() {
        let configuration = AppLaunchConfiguration(
            arguments: ["Orbit"],
            environment: ["ORBIT_USE_MOCKS": "1"]
        )

        XCTAssertEqual(configuration.mode, .mock)
    }

    func testNormalLaunchDefaultsToLiveMode() {
        let configuration = AppLaunchConfiguration(arguments: ["Orbit"], environment: [:])

        XCTAssertEqual(configuration.mode, .live)
    }

    func testMockModeBuildsMockDependencyGraph() {
        let dependencies = AppDependencies.make(
            for: AppLaunchConfiguration(arguments: ["Orbit", "--orbit-ui-tests"], environment: [:])
        )

        XCTAssertTrue(dependencies.todoAPIClient is MockTodoAPIClient)
        XCTAssertTrue(dependencies.billAPIClient is MockBillAPIClient)
        XCTAssertTrue(dependencies.memoryAPIClient is MockMemoryAPIClient)
        XCTAssertTrue(dependencies.moodAPIClient is MockMoodAPIClient)
        XCTAssertTrue(dependencies.projectAPIClient is MockProjectAPIClient)
        XCTAssertTrue(dependencies.chatAPIClient is MockChatAPIClient)
    }

    func testLiveModeBuildsRealDependencyGraph() {
        let dependencies = AppDependencies.make(
            for: AppLaunchConfiguration(arguments: ["Orbit"], environment: [:])
        )

        XCTAssertTrue(dependencies.todoAPIClient is OrbitAPIClient)
        XCTAssertTrue(dependencies.billAPIClient is OrbitAPIClient)
        XCTAssertTrue(dependencies.memoryAPIClient is OrbitAPIClient)
        XCTAssertTrue(dependencies.moodAPIClient is OrbitAPIClient)
        XCTAssertTrue(dependencies.projectAPIClient is OrbitAPIClient)
        XCTAssertTrue(dependencies.chatAPIClient is OrbitAPIClient)
    }

    func testMockModeProvidesStableSeedDataAndSuggestedActions() async throws {
        let dependencies = AppDependencies.mock()

        let todos = try await dependencies.todoAPIClient.listTodos()
        let bills = try await dependencies.billAPIClient.listBills()
        let memory = try await dependencies.memoryAPIClient.listMemory(
            includeArchived: false,
            kind: nil,
            tag: nil,
            projectId: nil
        )
        let response = try await dependencies.chatAPIClient.ask(
            AskRequest(question: "remember that I like quiet cafes")
        )
        let todoResponse = try await dependencies.chatAPIClient.ask(
            AskRequest(question: "add a todo to call the dentist tomorrow")
        )

        XCTAssertTrue(todos.contains { $0.title == "Review today plan" && !$0.isComplete })
        XCTAssertTrue(bills.contains { $0.name == "Credit card bill" && !$0.isPaid })
        XCTAssertTrue(memory.contains { $0.title == "AI article link" })
        XCTAssertEqual(response.suggestedActions?.map(\.type), ["save_memory"])
        XCTAssertEqual(
            response.suggestedActions?.first?.payload?["memory_text"],
            "I like quiet cafes"
        )
        XCTAssertEqual(
            response.suggestedActions?.first?.payload?["memory_title"],
            "Quiet cafes"
        )
        XCTAssertEqual(todoResponse.suggestedActions?.map(\.type), ["create_todo"])
        XCTAssertEqual(
            todoResponse.suggestedActions?.first?.payload?["draft_title"],
            "Call the dentist tomorrow"
        )
    }
}

final class OrbitAPIClientContractTests: XCTestCase {
    private let decoder = OrbitAPICoding.jsonDecoder
    private let encoder = OrbitAPICoding.jsonEncoder

    func testDecodesTodoDTOFromBackendJSON() throws {
        let todo = try decoder.decode(TodoDTO.self, from: Data("""
        {
          "id": "11111111-1111-1111-1111-111111111111",
          "title": "Plan day",
          "notes": "Review Orbit roadmap",
          "due_date": "2026-06-16",
          "project_id": null,
          "is_complete": false,
          "created_at": "2026-06-16T10:11:12.123456",
          "updated_at": "2026-06-16T10:11:12"
        }
        """.utf8))

        XCTAssertEqual(todo.id.uuidString, "11111111-1111-1111-1111-111111111111")
        XCTAssertEqual(todo.title, "Plan day")
        XCTAssertEqual(todo.notes, "Review Orbit roadmap")
        XCTAssertEqual(todo.dueDate.map(formatDateOnly), "2026-06-16")
        XCTAssertFalse(todo.isComplete)
        XCTAssertEqual(formatDateOnly(todo.createdAt), "2026-06-16")
    }

    func testDecodesBillDTOFromBackendJSON() throws {
        let bill = try decoder.decode(BillDTO.self, from: Data("""
        {
          "id": "22222222-2222-2222-2222-222222222222",
          "name": "Credit card",
          "amount": 4200.75,
          "currency": "INR",
          "due_date": "2026-06-20",
          "recurrence": "monthly",
          "is_paid": false,
          "reminder_days_before": 3,
          "notes": "Pay before statement date",
          "created_at": "2026-06-16T10:11:12.123456",
          "updated_at": "2026-06-16T10:11:12.123456"
        }
        """.utf8))

        XCTAssertEqual(bill.name, "Credit card")
        XCTAssertEqual(bill.amount, 4200.75)
        XCTAssertEqual(bill.currency, "INR")
        XCTAssertEqual(formatDateOnly(bill.dueDate), "2026-06-20")
        XCTAssertEqual(bill.recurrence, "monthly")
        XCTAssertEqual(bill.reminderDaysBefore, 3)
    }

    func testDecodesMemoryDTOFromBackendJSON() throws {
        let memory = try decoder.decode(MemoryDTO.self, from: Data("""
        {
          "id": "33333333-3333-3333-3333-333333333333",
          "title": "AI article",
          "body": "Save this for weekend reading.",
          "kind": "article",
          "source_url": "https://example.com/ai",
          "project_id": "55555555-5555-5555-5555-555555555555",
          "tags": ["ai", "reading"],
          "is_archived": false,
          "created_at": "2026-06-16T10:11:12Z",
          "updated_at": "2026-06-16T10:11:12Z"
        }
        """.utf8))

        XCTAssertEqual(memory.title, "AI article")
        XCTAssertEqual(memory.kind, "article")
        XCTAssertEqual(memory.sourceUrl, "https://example.com/ai")
        XCTAssertEqual(memory.projectId?.uuidString, "55555555-5555-5555-5555-555555555555")
        XCTAssertEqual(memory.tags, ["ai", "reading"])
        XCTAssertFalse(memory.isArchived)
    }

    func testDecodesMoodDTOFromBackendJSON() throws {
        let mood = try decoder.decode(MoodDTO.self, from: Data("""
        {
          "id": "44444444-4444-4444-4444-444444444444",
          "mood": "focused",
          "energy": 4,
          "notes": "Good deep work block.",
          "check_in_date": "2026-06-16",
          "created_at": "2026-06-16T10:11:12.123456",
          "updated_at": "2026-06-16T10:11:12.123456"
        }
        """.utf8))

        XCTAssertEqual(mood.mood, "focused")
        XCTAssertEqual(mood.energy, 4)
        XCTAssertEqual(mood.notes, "Good deep work block.")
        XCTAssertEqual(formatDateOnly(mood.checkInDate), "2026-06-16")
    }

    func testDecodesProjectDTOFromBackendJSON() throws {
        let project = try decoder.decode(ProjectDTO.self, from: Data("""
        {
          "id": "55555555-5555-5555-5555-555555555555",
          "name": "Orbit",
          "description": "Personal second brain app",
          "status": "active",
          "area": "personal",
          "tags": ["ios", "backend"],
          "created_at": "2026-06-16T10:11:12.123456",
          "updated_at": "2026-06-16T10:11:12.123456"
        }
        """.utf8))

        XCTAssertEqual(project.name, "Orbit")
        XCTAssertEqual(project.description, "Personal second brain app")
        XCTAssertEqual(project.status, "active")
        XCTAssertEqual(project.area, "personal")
        XCTAssertEqual(project.tags, ["ios", "backend"])
    }

    func testDecodesChatSessionDTOFromBackendJSON() throws {
        let session = try decoder.decode(ChatSessionDTO.self, from: Data("""
        {
          "id": "66666666-6666-6666-6666-666666666666",
          "title": "What should I focus on today?",
          "created_at": "2026-06-16T10:11:12.123456",
          "updated_at": "2026-06-16T10:12:12.123456"
        }
        """.utf8))

        XCTAssertEqual(session.id.uuidString, "66666666-6666-6666-6666-666666666666")
        XCTAssertEqual(session.title, "What should I focus on today?")
        XCTAssertEqual(formatDateOnly(session.createdAt), "2026-06-16")
    }

    func testDecodesChatMessageDTOFromBackendJSON() throws {
        let message = try decoder.decode(ChatMessageDTO.self, from: Data("""
        {
          "id": "77777777-7777-7777-7777-777777777777",
          "session_id": "66666666-6666-6666-6666-666666666666",
          "role": "assistant",
          "content": "Based on available Orbit context...",
          "created_at": "2026-06-16T10:11:12.123456"
        }
        """.utf8))

        XCTAssertEqual(message.id.uuidString, "77777777-7777-7777-7777-777777777777")
        XCTAssertEqual(message.sessionId.uuidString, "66666666-6666-6666-6666-666666666666")
        XCTAssertEqual(message.role, "assistant")
        XCTAssertEqual(message.content, "Based on available Orbit context...")
    }

    func testDecodesAskResponseFromBackendJSON() throws {
        let response = try decoder.decode(AskResponse.self, from: Data("""
        {
          "session": {
            "id": "66666666-6666-6666-6666-666666666666",
            "title": "What should I focus on today?",
            "created_at": "2026-06-16T10:11:12.123456",
            "updated_at": "2026-06-16T10:12:12.123456"
          },
          "user_message": {
            "id": "77777777-7777-7777-7777-777777777777",
            "session_id": "66666666-6666-6666-6666-666666666666",
            "role": "user",
            "content": "What should I focus on today?",
            "created_at": "2026-06-16T10:11:12.123456"
          },
          "assistant_message": {
            "id": "88888888-8888-8888-8888-888888888888",
            "session_id": "66666666-6666-6666-6666-666666666666",
            "role": "assistant",
            "content": "Based on available Orbit context...",
            "created_at": "2026-06-16T10:11:13.123456"
          },
          "answer": "Based on available Orbit context...",
          "context_sections": ["Today", "Open todos"],
          "context_summary": "Context used: Today, Open todos",
          "suggested_actions": [
            {
              "id": "review-bills",
              "type": "review_bills",
              "title": "Review bills",
              "subtitle": "Check overdue and upcoming bills",
              "payload": null
            }
          ]
        }
        """.utf8))

        XCTAssertEqual(response.session.title, "What should I focus on today?")
        XCTAssertEqual(response.userMessage.role, "user")
        XCTAssertEqual(response.assistantMessage.role, "assistant")
        XCTAssertEqual(response.answer, "Based on available Orbit context...")
        XCTAssertEqual(response.contextSections, ["Today", "Open todos"])
        XCTAssertEqual(response.contextSummary, "Context used: Today, Open todos")
        XCTAssertEqual(response.suggestedActions?.map(\.type), ["review_bills"])
        XCTAssertEqual(response.suggestedActions?.first?.title, "Review bills")
        XCTAssertNil(response.retrievalDiagnostics)
    }

    func testDecodesOlderAskResponseWithoutContextSummary() throws {
        let response = try decoder.decode(AskResponse.self, from: Data("""
        {
          "session": {
            "id": "66666666-6666-6666-6666-666666666666",
            "title": "Older response",
            "created_at": "2026-06-16T10:11:12.123456",
            "updated_at": "2026-06-16T10:12:12.123456"
          },
          "user_message": {
            "id": "77777777-7777-7777-7777-777777777777",
            "session_id": "66666666-6666-6666-6666-666666666666",
            "role": "user",
            "content": "Question",
            "created_at": "2026-06-16T10:11:12.123456"
          },
          "assistant_message": {
            "id": "88888888-8888-8888-8888-888888888888",
            "session_id": "66666666-6666-6666-6666-666666666666",
            "role": "assistant",
            "content": "Answer",
            "created_at": "2026-06-16T10:11:13.123456"
          },
          "answer": "Answer"
        }
        """.utf8))

        XCTAssertNil(response.contextSections)
        XCTAssertNil(response.contextSummary)
        XCTAssertNil(response.suggestedActions)
    }

    func testDecodesAskContextPreviewResponseFromBackendJSON() throws {
        let response = try decoder.decode(AskContextPreviewResponse.self, from: Data("""
        {
          "question": "What did I save about AI?",
          "include_context": true,
          "context": "Today:\\n- 2026-06-17\\n\\nRecent memory:\\n- AI retrieval notes",
          "context_sections": ["Today", "Recent memory"],
          "retrieval_diagnostics": {
            "retrieval_mode": "hybrid",
            "memory_top_k": 8,
            "min_vector_score": 0.25,
            "vector_attempted": true,
            "vector_result_count": 3,
            "vector_error": null,
            "fallback_used": false,
            "context_build_ms": 2.75
          }
        }
        """.utf8))

        XCTAssertEqual(response.question, "What did I save about AI?")
        XCTAssertTrue(response.includeContext)
        XCTAssertTrue(response.context.contains("AI retrieval notes"))
        XCTAssertEqual(response.contextSections, ["Today", "Recent memory"])
        XCTAssertEqual(response.retrievalDiagnostics?.retrievalMode, .hybrid)
        XCTAssertEqual(response.retrievalDiagnostics?.memoryTopK, 8)
        XCTAssertEqual(response.retrievalDiagnostics?.minVectorScore, 0.25)
        XCTAssertEqual(response.retrievalDiagnostics?.vectorAttempted, true)
        XCTAssertEqual(response.retrievalDiagnostics?.vectorResultCount, 3)
        XCTAssertNil(response.retrievalDiagnostics?.vectorError)
        XCTAssertEqual(response.retrievalDiagnostics?.fallbackUsed, false)
        XCTAssertEqual(response.retrievalDiagnostics?.contextBuildMs, 2.75)
    }

    func testEncodesTodoCreateRequestWithSnakeCaseAndDateOnly() throws {
        let payload = TodoCreateRequest(
            title: "Plan launch",
            notes: "Write tasks",
            dueDate: makeDate(year: 2026, month: 6, day: 16),
            projectId: UUID(uuidString: "55555555-5555-5555-5555-555555555555"),
            isComplete: false
        )

        let json = try encodeJSONObject(payload)

        XCTAssertEqual(json["title"] as? String, "Plan launch")
        XCTAssertEqual(json["notes"] as? String, "Write tasks")
        XCTAssertEqual(json["due_date"] as? String, "2026-06-16")
        XCTAssertEqual(json["project_id"] as? String, "55555555-5555-5555-5555-555555555555")
        XCTAssertEqual(json["is_complete"] as? Bool, false)
    }

    func testEncodesBillCreateRequestWithSnakeCaseAndDateOnly() throws {
        let payload = BillCreateRequest(
            name: "Furlenco rent",
            amount: 1800,
            currency: "INR",
            dueDate: makeDate(year: 2026, month: 6, day: 20),
            recurrence: "monthly",
            isPaid: false,
            reminderDaysBefore: 3,
            notes: "Autopay backup"
        )

        let json = try encodeJSONObject(payload)

        XCTAssertEqual(json["name"] as? String, "Furlenco rent")
        XCTAssertEqual(json["amount"] as? Double, 1800)
        XCTAssertEqual(json["currency"] as? String, "INR")
        XCTAssertEqual(json["due_date"] as? String, "2026-06-20")
        XCTAssertEqual(json["recurrence"] as? String, "monthly")
        XCTAssertEqual(json["is_paid"] as? Bool, false)
        XCTAssertEqual(json["reminder_days_before"] as? Int, 3)
    }

    func testEncodesMemoryCreateRequestWithSnakeCase() throws {
        let payload = MemoryCreateRequest(
            title: "WorldLens project update",
            body: "Prototype review notes",
            kind: "project_update",
            sourceUrl: "https://example.com/worldlens",
            tags: ["worldlens", "review"],
            isArchived: false
        )

        let json = try encodeJSONObject(payload)

        XCTAssertEqual(json["title"] as? String, "WorldLens project update")
        XCTAssertEqual(json["body"] as? String, "Prototype review notes")
        XCTAssertEqual(json["kind"] as? String, "project_update")
        XCTAssertEqual(json["source_url"] as? String, "https://example.com/worldlens")
        XCTAssertEqual(json["tags"] as? [String], ["worldlens", "review"])
        XCTAssertEqual(json["is_archived"] as? Bool, false)
    }

    func testEncodesMemoryProjectLinkWithSnakeCase() throws {
        let payload = MemoryProjectLinkRequest(
            projectId: UUID(uuidString: "55555555-5555-5555-5555-555555555555")
        )

        let json = try encodeJSONObject(payload)

        XCTAssertEqual(json["project_id"] as? String, "55555555-5555-5555-5555-555555555555")
    }

    func testEncodesMemoryProjectUnlinkAsExplicitNull() throws {
        let json = try encodeJSONObject(MemoryProjectLinkRequest(projectId: nil))

        XCTAssertTrue(json.keys.contains("project_id"))
        XCTAssertTrue(json["project_id"] is NSNull)
    }

    func testListMemoryCanRequestProjectFilter() async throws {
        StubURLProtocol.lastRequest = nil
        StubURLProtocol.response = HTTPURLResponse(
            url: URL(string: "https://orbit.test/memory")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )
        StubURLProtocol.responseData = Data("[]".utf8)

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let client = OrbitAPIClient(baseURL: URL(string: "https://orbit.test")!, session: session)

        _ = try await client.listMemory(
            includeArchived: false,
            kind: nil,
            tag: nil,
            projectId: UUID(uuidString: "55555555-5555-5555-5555-555555555555")
        )

        let request = try XCTUnwrap(StubURLProtocol.lastRequest)
        let components = try XCTUnwrap(URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false))
        let queryItems = components.queryItems ?? []
        XCTAssertEqual(queryItems.first { $0.name == "project_id" }?.value, "55555555-5555-5555-5555-555555555555")
        XCTAssertEqual(queryItems.first { $0.name == "include_archived" }?.value, "false")
    }

    func testListTodosCanRequestProjectFilter() async throws {
        StubURLProtocol.lastRequest = nil
        StubURLProtocol.response = HTTPURLResponse(
            url: URL(string: "https://orbit.test/todos")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )
        StubURLProtocol.responseData = Data("[]".utf8)

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let client = OrbitAPIClient(baseURL: URL(string: "https://orbit.test")!, session: session)

        _ = try await client.listTodos(projectId: UUID(uuidString: "55555555-5555-5555-5555-555555555555"))

        let request = try XCTUnwrap(StubURLProtocol.lastRequest)
        let components = try XCTUnwrap(URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false))
        let queryItems = components.queryItems ?? []
        XCTAssertEqual(queryItems.first { $0.name == "project_id" }?.value, "55555555-5555-5555-5555-555555555555")
    }

    func testEncodesMoodCreateRequestWithSnakeCaseAndDateOnly() throws {
        let payload = MoodCreateRequest(
            mood: "calm",
            energy: 3,
            notes: "Low noise morning.",
            checkInDate: makeDate(year: 2026, month: 6, day: 16)
        )

        let json = try encodeJSONObject(payload)

        XCTAssertEqual(json["mood"] as? String, "calm")
        XCTAssertEqual(json["energy"] as? Int, 3)
        XCTAssertEqual(json["notes"] as? String, "Low noise morning.")
        XCTAssertEqual(json["check_in_date"] as? String, "2026-06-16")
    }

    func testEncodesProjectCreateRequestWithSnakeCase() throws {
        let payload = ProjectCreateRequest(
            name: "AI Systems Learning",
            description: "Study plan",
            status: "active",
            area: "learning",
            tags: ["ai", "systems"]
        )

        let json = try encodeJSONObject(payload)

        XCTAssertEqual(json["name"] as? String, "AI Systems Learning")
        XCTAssertEqual(json["description"] as? String, "Study plan")
        XCTAssertEqual(json["status"] as? String, "active")
        XCTAssertEqual(json["area"] as? String, "learning")
        XCTAssertEqual(json["tags"] as? [String], ["ai", "systems"])
    }

    func testEncodesAskRequestWithSnakeCase() throws {
        let payload = AskRequest(
            question: "What should I focus on today?",
            sessionId: UUID(uuidString: "66666666-6666-6666-6666-666666666666"),
            includeContext: true
        )

        let json = try encodeJSONObject(payload)

        XCTAssertEqual(json["question"] as? String, "What should I focus on today?")
        XCTAssertEqual(json["session_id"] as? String, "66666666-6666-6666-6666-666666666666")
        XCTAssertEqual(json["include_context"] as? Bool, true)
        XCTAssertEqual(json["retrieval_mode"] as? String, "keyword")
        XCTAssertEqual(json["memory_top_k"] as? Int, 5)
        XCTAssertEqual(json["min_vector_score"] as? Double, 0.0)
    }

    func testEncodesHybridAskRequestControls() throws {
        let payload = AskRequest(
            question: "What did I save about AI?",
            sessionId: nil,
            includeContext: true,
            retrievalMode: .hybrid,
            memoryTopK: 8,
            minVectorScore: 0.25
        )

        let json = try encodeJSONObject(payload)

        XCTAssertEqual(json["retrieval_mode"] as? String, "hybrid")
        XCTAssertEqual(json["memory_top_k"] as? Int, 8)
        XCTAssertEqual(json["min_vector_score"] as? Double, 0.25)
    }

    func testEncodesAskContextPreviewRequestWithSnakeCase() throws {
        let payload = AskContextPreviewRequest(
            question: "What did I save about AI?",
            includeContext: false
        )

        let json = try encodeJSONObject(payload)

        XCTAssertEqual(json["question"] as? String, "What did I save about AI?")
        XCTAssertEqual(json["include_context"] as? Bool, false)
        XCTAssertEqual(json["retrieval_mode"] as? String, "keyword")
        XCTAssertEqual(json["memory_top_k"] as? Int, 5)
        XCTAssertEqual(json["min_vector_score"] as? Double, 0.0)
    }

    func testNonSuccessAPIResponseMapsToReadableRequestFailedError() async throws {
        StubURLProtocol.response = HTTPURLResponse(
            url: URL(string: "https://orbit.test/todos")!,
            statusCode: 500,
            httpVersion: nil,
            headerFields: nil
        )
        StubURLProtocol.responseData = Data("Backend unavailable".utf8)

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let client = OrbitAPIClient(baseURL: URL(string: "https://orbit.test")!, session: session)

        do {
            let _: [TodoDTO] = try await client.listTodos()
            XCTFail("Expected request to fail.")
        } catch let error as OrbitAPIError {
            guard case let .requestFailed(statusCode, message) = error else {
                return XCTFail("Expected requestFailed, got \(error).")
            }
            XCTAssertEqual(statusCode, 500)
            XCTAssertEqual(message, "Backend unavailable")
            XCTAssertEqual(error.errorDescription, "Backend unavailable")
        }
    }

    private func encodeJSONObject<T: Encodable>(_ value: T) throws -> [String: Any] {
        let data = try encoder.encode(value)
        let object = try JSONSerialization.jsonObject(with: data)
        return try XCTUnwrap(object as? [String: Any])
    }

    private func makeDate(year: Int, month: Int, day: Int) -> Date {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = year
        components.month = month
        components.day = day
        return components.date!
    }

    private func formatDateOnly(_ date: Date) -> String {
        OrbitAPICoding.makeDateOnlyFormatter().string(from: date)
    }
}

private final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var response: HTTPURLResponse?
    nonisolated(unsafe) static var responseData = Data()
    nonisolated(unsafe) static var lastRequest: URLRequest?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        lastRequest = request
        return request
    }

    override func startLoading() {
        if let response = Self.response {
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        }
        client?.urlProtocol(self, didLoad: Self.responseData)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

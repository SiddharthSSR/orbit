import XCTest
@testable import Orbit

@MainActor
final class TodayDashboardViewModelTests: XCTestCase {
    func testLoadDashboardLoadsTodosBillsAndMemory() async {
        let viewModel = makeViewModel(
            todos: [makeTodo(title: "Open todo")],
            bills: [makeBill(name: "Rent")],
            memoryItems: [makeMemory(title: "Idea")],
            moods: [makeMood(mood: "focused")]
        )

        await viewModel.loadDashboard()

        XCTAssertEqual(viewModel.todos.map(\.title), ["Open todo"])
        XCTAssertEqual(viewModel.bills.map(\.name), ["Rent"])
        XCTAssertEqual(viewModel.memoryItems.map(\.title), ["Idea"])
        XCTAssertEqual(viewModel.latestMood?.mood, "focused")
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testOpenTodosOnlyExcludesCompletedTodos() async {
        let viewModel = makeViewModel(todos: [
            makeTodo(title: "Open"),
            makeTodo(title: "Done", isComplete: true)
        ])

        await viewModel.loadDashboard()

        XCTAssertEqual(viewModel.openTodos.map(\.title), ["Open"])
        XCTAssertEqual(viewModel.openTodoCount, 1)
    }

    func testDisplayedOpenTodosPlacesHighlightedTodoFirst() async {
        let dueTodo = makeTodo(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            title: "Due first",
            dueDate: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let highlightedTodo = makeTodo(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            title: "Just created"
        )
        let viewModel = makeViewModel(todos: [dueTodo, highlightedTodo])
        await viewModel.loadDashboard()

        XCTAssertEqual(
            viewModel.displayedOpenTodos(highlighting: highlightedTodo.id).map(\.title),
            ["Just created", "Due first"]
        )
    }

    func testDisplayedOpenTodosOrdersDatedTodosBeforeUndatedTodosByDueDate() async {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let later = makeTodo(title: "Later", dueDate: base.addingTimeInterval(86_400))
        let undated = makeTodo(title: "Undated", createdAt: base.addingTimeInterval(200))
        let earlier = makeTodo(title: "Earlier", dueDate: base)
        let viewModel = makeViewModel(todos: [later, undated, earlier])
        await viewModel.loadDashboard()

        XCTAssertEqual(viewModel.openTodos.map(\.title), ["Earlier", "Later", "Undated"])
    }

    func testDisplayedOpenTodosUsesCreatedDateThenIDForStableFallbackOrdering() async {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let lowerID = makeTodo(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            title: "Lower ID",
            createdAt: base
        )
        let higherID = makeTodo(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            title: "Higher ID",
            createdAt: base
        )
        let newest = makeTodo(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
            title: "Newest",
            createdAt: base.addingTimeInterval(1)
        )
        let expected = ["Newest", "Lower ID", "Higher ID"]
        let firstViewModel = makeViewModel(todos: [higherID, newest, lowerID])
        let secondViewModel = makeViewModel(todos: [lowerID, higherID, newest])
        await firstViewModel.loadDashboard()
        await secondViewModel.loadDashboard()

        XCTAssertEqual(firstViewModel.openTodos.map(\.title), expected)
        XCTAssertEqual(secondViewModel.openTodos.map(\.title), expected)
    }

    func testTodoUrgencyResolvesRelativeDueDateLabels() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let today = Date(timeIntervalSince1970: 1_700_006_400)

        XCTAssertEqual(
            TodoUrgency.resolve(
                dueDate: calendar.date(byAdding: .day, value: -1, to: today),
                relativeTo: today,
                calendar: calendar
            )?.label,
            "Overdue"
        )
        XCTAssertEqual(
            TodoUrgency.resolve(dueDate: today, relativeTo: today, calendar: calendar)?.label,
            "Due today"
        )
        XCTAssertEqual(
            TodoUrgency.resolve(
                dueDate: calendar.date(byAdding: .day, value: 1, to: today),
                relativeTo: today,
                calendar: calendar
            )?.label,
            "Due tomorrow"
        )
        XCTAssertNil(TodoUrgency.resolve(dueDate: nil, relativeTo: today, calendar: calendar))
    }

    func testUnpaidBillsOnlyExcludesPaidBills() async {
        let viewModel = makeViewModel(bills: [
            makeBill(name: "Unpaid"),
            makeBill(name: "Paid", isPaid: true)
        ])

        await viewModel.loadDashboard()

        XCTAssertEqual(viewModel.unpaidBills.map(\.name), ["Unpaid"])
        XCTAssertEqual(viewModel.unpaidBillCount, 1)
    }

    func testToggleTodoCompleteRemovesCompletedTodoFromOpenList() async {
        let todo = makeTodo(title: "File receipt")
        let viewModel = makeViewModel(todos: [todo])

        await viewModel.loadDashboard()
        await viewModel.toggleTodoComplete(todo: todo)

        XCTAssertTrue(viewModel.openTodos.isEmpty)
        XCTAssertEqual(viewModel.todos.first?.isComplete, true)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testToggleTodoCompleteTracksInFlightState() async {
        let todo = makeTodo(title: "File receipt")
        let client = SuspendedDashboardTodoAPIClient(todo: todo)
        let viewModel = TodayDashboardViewModel(
            todoAPIClient: client,
            billAPIClient: MockBillAPIClient(bills: []),
            memoryAPIClient: MockMemoryAPIClient(memoryItems: []),
            moodAPIClient: MockMoodAPIClient(moods: [])
        )
        await viewModel.loadDashboard()

        let completion = Task { await viewModel.toggleTodoComplete(todo: todo) }
        await client.waitUntilUpdateStarts()

        XCTAssertTrue(viewModel.isCompletingTodo(id: todo.id))

        await viewModel.toggleTodoComplete(todo: todo)
        let updateCallCount = await client.recordedUpdateCallCount()
        XCTAssertEqual(updateCallCount, 1)

        await client.resumeUpdate()
        await completion.value

        XCTAssertFalse(viewModel.isCompletingTodo(id: todo.id))
        XCTAssertTrue(viewModel.openTodos.isEmpty)
    }

    func testFailedTodoCompletionLeavesTodoVisibleAndShowsInlineError() async {
        let todo = makeTodo(title: "File receipt")
        let viewModel = TodayDashboardViewModel(
            todoAPIClient: FailingUpdateDashboardTodoAPIClient(todo: todo),
            billAPIClient: MockBillAPIClient(bills: []),
            memoryAPIClient: MockMemoryAPIClient(memoryItems: []),
            moodAPIClient: MockMoodAPIClient(moods: [])
        )
        await viewModel.loadDashboard()

        await viewModel.toggleTodoComplete(todo: todo)

        XCTAssertEqual(viewModel.openTodos.map(\.title), ["File receipt"])
        XCTAssertEqual(viewModel.todoCompletionErrorMessage, "Expected todo completion failure.")
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.isCompletingTodo(id: todo.id))
    }

    func testToggleBillPaidRemovesPaidBillFromUnpaidList() async {
        let bill = makeBill(name: "Credit card")
        let viewModel = makeViewModel(bills: [bill])

        await viewModel.loadDashboard()
        await viewModel.toggleBillPaid(bill: bill)

        XCTAssertTrue(viewModel.unpaidBills.isEmpty)
        XCTAssertEqual(viewModel.bills.first?.isPaid, true)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testArchiveMemoryRemovesArchivedMemoryFromRecentList() async {
        let memory = makeMemory(title: "Archive me")
        let viewModel = makeViewModel(memoryItems: [memory])

        await viewModel.loadDashboard()
        await viewModel.archiveMemory(memory: memory)

        XCTAssertTrue(viewModel.recentMemoryItems.isEmpty)
        XCTAssertTrue(viewModel.memoryItems.isEmpty)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testDashboardLimitsDisplayedItemsToFive() async {
        let viewModel = makeViewModel(
            todos: (1...6).map { makeTodo(title: "Todo \($0)") },
            bills: (1...6).map { makeBill(name: "Bill \($0)") },
            memoryItems: (1...6).map { makeMemory(title: "Memory \($0)") }
        )

        await viewModel.loadDashboard()

        XCTAssertEqual(viewModel.openTodos.count, 5)
        XCTAssertEqual(viewModel.unpaidBills.count, 5)
        XCTAssertEqual(viewModel.recentMemoryItems.count, 5)
    }

    func testLoadDashboardLoadsLatestMood() async {
        let viewModel = makeViewModel(moods: [
            makeMood(mood: "focused", energy: 4),
            makeMood(mood: "tired", energy: 2)
        ])

        await viewModel.loadDashboard()

        XCTAssertEqual(viewModel.latestMood?.mood, "focused")
        XCTAssertEqual(viewModel.latestMood?.energy, 4)
    }

    func testErrorStateIsSetWhenOneAPIFails() async {
        let viewModel = TodayDashboardViewModel(
            todoAPIClient: MockTodoAPIClient(todos: []),
            billAPIClient: FailingDashboardBillAPIClient(),
            memoryAPIClient: MockMemoryAPIClient(memoryItems: []),
            moodAPIClient: MockMoodAPIClient(moods: [])
        )

        await viewModel.loadDashboard()

        XCTAssertEqual(viewModel.errorMessage, "Expected dashboard API failure.")
        XCTAssertFalse(viewModel.isLoading)
    }

    func testToggleTodoCompleteEmitsTodoRefreshEvent() async {
        let center = NotificationCenter()
        let todo = makeTodo(title: "Finish report")
        let viewModel = makeViewModel(todos: [todo], notificationCenter: center)
        await viewModel.loadDashboard()
        let event = XCTNSNotificationExpectation(name: .orbitTodoDidChange, object: nil, notificationCenter: center)

        await viewModel.toggleTodoComplete(todo: todo)

        await fulfillment(of: [event], timeout: 0.5)
    }

    func testToggleBillPaidEmitsBillsRefreshEvent() async {
        let center = NotificationCenter()
        let bill = makeBill(name: "Electricity")
        let viewModel = makeViewModel(bills: [bill], notificationCenter: center)
        await viewModel.loadDashboard()
        let event = XCTNSNotificationExpectation(name: .orbitBillsDidChange, object: nil, notificationCenter: center)

        await viewModel.toggleBillPaid(bill: bill)

        await fulfillment(of: [event], timeout: 0.5)
    }

    func testArchiveMemoryEmitsMemoryRefreshEvent() async {
        let center = NotificationCenter()
        let memory = makeMemory(title: "Old note")
        let viewModel = makeViewModel(memoryItems: [memory], notificationCenter: center)
        await viewModel.loadDashboard()
        let event = XCTNSNotificationExpectation(name: .orbitMemoryDidChange, object: nil, notificationCenter: center)

        await viewModel.archiveMemory(memory: memory)

        await fulfillment(of: [event], timeout: 0.5)
    }

    func testFailedTodayMutationDoesNotEmitRefreshEvent() async {
        let center = NotificationCenter()
        let todo = makeTodo(title: "Finish report")
        let viewModel = TodayDashboardViewModel(
            todoAPIClient: FailingDashboardTodoAPIClient(),
            billAPIClient: MockBillAPIClient(bills: []),
            memoryAPIClient: MockMemoryAPIClient(memoryItems: []),
            moodAPIClient: MockMoodAPIClient(moods: []),
            notificationCenter: center
        )
        let event = XCTNSNotificationExpectation(name: .orbitTodoDidChange, object: nil, notificationCenter: center)
        event.isInverted = true

        await viewModel.toggleTodoComplete(todo: todo)

        await fulfillment(of: [event], timeout: 0.3)
    }

    func testUpdateTodoProjectLinkUpdatesLocalTodoState() async {
        let todo = makeTodo(title: "Plan launch")
        let project = makeProject(name: "Orbit")
        let viewModel = TodayDashboardViewModel(
            todoAPIClient: MockTodoAPIClient(todos: [todo]),
            billAPIClient: MockBillAPIClient(bills: []),
            memoryAPIClient: MockMemoryAPIClient(memoryItems: []),
            moodAPIClient: MockMoodAPIClient(moods: []),
            projectAPIClient: MockProjectAPIClient(projects: [project])
        )
        await viewModel.loadDashboard()
        await viewModel.loadProjects()

        await viewModel.updateTodoProjectLink(todo: todo, projectID: project.id)
        XCTAssertEqual(viewModel.todos.first?.projectId, project.id)
        XCTAssertEqual(viewModel.projectName(for: project.id), "Orbit")
        XCTAssertNil(viewModel.todoProjectLinkErrors[todo.id])

        let linkedTodo = viewModel.todos.first!
        await viewModel.updateTodoProjectLink(todo: linkedTodo, projectID: nil)
        XCTAssertNil(viewModel.todos.first?.projectId)
    }

    func testProjectLoadFailureDoesNotBreakTodoList() async {
        let todo = makeTodo(title: "Plan launch")
        let viewModel = TodayDashboardViewModel(
            todoAPIClient: MockTodoAPIClient(todos: [todo]),
            billAPIClient: MockBillAPIClient(bills: []),
            memoryAPIClient: MockMemoryAPIClient(memoryItems: []),
            moodAPIClient: MockMoodAPIClient(moods: []),
            projectAPIClient: FailingDashboardProjectAPIClient()
        )
        await viewModel.loadDashboard()
        await viewModel.loadProjects()

        XCTAssertEqual(viewModel.todos.map(\.title), ["Plan launch"])
        XCTAssertTrue(viewModel.projects.isEmpty)
        XCTAssertNotNil(viewModel.projectLoadErrorMessage)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testProjectDigestCountsLinkedTodosAndMemory() {
        let projectID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let project = makeProject(id: projectID, name: "Orbit")

        let digest = TodayProjectDigestItem.derive(
            projects: [project],
            todos: [
                makeTodo(title: "Open", projectId: projectID),
                makeTodo(title: "Done", projectId: projectID, isComplete: true),
                makeTodo(title: "Unlinked")
            ],
            memoryItems: [
                makeMemory(title: "Linked note", projectId: projectID),
                makeMemory(title: "Unlinked note")
            ]
        )

        XCTAssertEqual(digest.count, 1)
        XCTAssertEqual(digest.first?.project.name, "Orbit")
        XCTAssertEqual(digest.first?.openTodoCount, 1)
        XCTAssertEqual(digest.first?.completedTodoCount, 1)
        XCTAssertEqual(digest.first?.memoryCount, 1)
    }

    func testProjectDigestChoosesEarliestDueOpenTodo() {
        let projectID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let project = makeProject(id: projectID, name: "Orbit")
        let later = Date(timeIntervalSince1970: 1_700_086_400)
        let earlier = Date(timeIntervalSince1970: 1_700_000_000)

        let digest = TodayProjectDigestItem.derive(
            projects: [project],
            todos: [
                makeTodo(title: "Later", dueDate: later, projectId: projectID),
                makeTodo(title: "Earlier", dueDate: earlier, projectId: projectID),
                makeTodo(title: "Completed first", dueDate: earlier.addingTimeInterval(-86_400), projectId: projectID, isComplete: true)
            ],
            memoryItems: []
        )

        XCTAssertEqual(digest.first?.nextDueTodo?.title, "Earlier")
    }

    func testProjectDigestIgnoresUnlinkedActivityAndHandlesEmptyInput() {
        let project = makeProject(name: "Orbit")

        let digest = TodayProjectDigestItem.derive(
            projects: [project],
            todos: [makeTodo(title: "Unlinked")],
            memoryItems: [makeMemory(title: "Unlinked note")]
        )

        XCTAssertTrue(digest.isEmpty)
        XCTAssertTrue(TodayProjectDigestItem.derive(projects: [], todos: [], memoryItems: []).isEmpty)
    }

    func testProjectDigestSortsByNextDueThenOpenCount() {
        let urgentID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        let busyID = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
        let quietID = UUID(uuidString: "55555555-5555-5555-5555-555555555555")!
        let dueTomorrow = Date(timeIntervalSince1970: 1_700_086_400)

        let digest = TodayProjectDigestItem.derive(
            projects: [
                makeProject(id: quietID, name: "Quiet"),
                makeProject(id: busyID, name: "Busy"),
                makeProject(id: urgentID, name: "Urgent")
            ],
            todos: [
                makeTodo(title: "Busy one", projectId: busyID),
                makeTodo(title: "Busy two", projectId: busyID),
                makeTodo(title: "Quiet one", projectId: quietID),
                makeTodo(title: "Due soon", dueDate: dueTomorrow, projectId: urgentID)
            ],
            memoryItems: []
        )

        XCTAssertEqual(digest.map(\.project.name), ["Urgent", "Busy", "Quiet"])
    }

    func testProjectDigestNextDueCueForOverdueTodo() {
        XCTAssertEqual(digestCue(dueOffsetDays: -1), "Overdue: Linked task")
    }

    func testProjectDigestNextDueCueForDueTodayTodo() {
        XCTAssertEqual(digestCue(dueOffsetDays: 0), "Due today: Linked task")
    }

    func testProjectDigestNextDueCueForUpcomingTodoIncludesDate() {
        let cue = digestCue(dueOffsetDays: 3)
        XCTAssertTrue(
            cue?.hasPrefix("Next: Linked task · ") == true,
            "Unexpected upcoming cue: \(cue ?? "nil")"
        )
    }

    func testProjectDigestNextDueCueIgnoresCompletedAndUndatedTodos() {
        let item = makeDigestItem(todos: [
            makeTodo(title: "Done", dueDate: digestCueNow, projectId: digestCueProjectID, isComplete: true),
            makeTodo(title: "Undated open", projectId: digestCueProjectID)
        ])
        XCTAssertNotNil(item, "Project with linked todos should still appear in the digest")
        XCTAssertNil(item?.nextDueCue(relativeTo: digestCueNow, calendar: digestCueCalendar))
    }

    private let digestCueProjectID = UUID(uuidString: "66666666-6666-6666-6666-666666666666")!

    private var digestCueNow: Date { Date(timeIntervalSince1970: 1_700_006_400) }

    private var digestCueCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func makeDigestItem(todos: [TodoDTO]) -> TodayProjectDigestItem? {
        TodayProjectDigestItem.derive(
            projects: [makeProject(id: digestCueProjectID, name: "Orbit")],
            todos: todos,
            memoryItems: []
        ).first
    }

    private func digestCue(dueOffsetDays: Int) -> String? {
        let due = digestCueCalendar.date(byAdding: .day, value: dueOffsetDays, to: digestCueNow)!
        let item = makeDigestItem(todos: [
            makeTodo(title: "Linked task", dueDate: due, projectId: digestCueProjectID)
        ])
        return item?.nextDueCue(relativeTo: digestCueNow, calendar: digestCueCalendar)
    }

    private func makeProject(
        id: UUID = UUID(),
        name: String,
        status: String = "active",
        updatedAt: Date = Date(timeIntervalSince1970: 1_700_000_000)
    ) -> ProjectDTO {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        return ProjectDTO(
            id: id,
            name: name,
            description: nil,
            status: status,
            area: nil,
            tags: [],
            createdAt: now,
            updatedAt: updatedAt
        )
    }

    private func makeViewModel(
        todos: [TodoDTO] = [],
        bills: [BillDTO] = [],
        memoryItems: [MemoryDTO] = [],
        moods: [MoodDTO] = [],
        notificationCenter: NotificationCenter = .default
    ) -> TodayDashboardViewModel {
        TodayDashboardViewModel(
            todoAPIClient: MockTodoAPIClient(todos: todos),
            billAPIClient: MockBillAPIClient(bills: bills),
            memoryAPIClient: MockMemoryAPIClient(memoryItems: memoryItems),
            moodAPIClient: MockMoodAPIClient(moods: moods),
            notificationCenter: notificationCenter
        )
    }

    private func makeTodo(
        id: UUID = UUID(),
        title: String,
        dueDate: Date? = nil,
        projectId: UUID? = nil,
        isComplete: Bool = false,
        createdAt: Date = Date(timeIntervalSince1970: 1_700_000_000)
    ) -> TodoDTO {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        return TodoDTO(
            id: id,
            title: title,
            notes: nil,
            dueDate: dueDate,
            projectId: projectId,
            isComplete: isComplete,
            createdAt: createdAt,
            updatedAt: now
        )
    }

    private func makeBill(name: String, isPaid: Bool = false) -> BillDTO {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        return BillDTO(
            id: UUID(),
            name: name,
            amount: 1200,
            currency: "INR",
            dueDate: now,
            recurrence: nil,
            isPaid: isPaid,
            reminderDaysBefore: 3,
            notes: nil,
            createdAt: now,
            updatedAt: now
        )
    }

    private func makeMemory(
        title: String,
        projectId: UUID? = nil,
        isArchived: Bool = false
    ) -> MemoryDTO {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        return MemoryDTO(
            id: UUID(),
            title: title,
            body: "Body",
            kind: "note",
            sourceUrl: nil,
            projectId: projectId,
            tags: ["today"],
            isArchived: isArchived,
            createdAt: now,
            updatedAt: now
        )
    }

    private func makeMood(mood: String, energy: Int = 3) -> MoodDTO {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        return MoodDTO(
            id: UUID(),
            mood: mood,
            energy: energy,
            notes: nil,
            checkInDate: now,
            createdAt: now,
            updatedAt: now
        )
    }
}

private struct FailingDashboardBillAPIClient: BillAPIClientProtocol {
    func listBills() async throws -> [BillDTO] {
        throw FailingDashboardAPIError.expectedFailure
    }

    func createBill(_ payload: BillCreateRequest) async throws -> BillDTO {
        throw FailingDashboardAPIError.expectedFailure
    }

    func updateBill(id: UUID, payload: BillUpdateRequest) async throws -> BillDTO {
        throw FailingDashboardAPIError.expectedFailure
    }

    func deleteBill(id: UUID) async throws {
        throw FailingDashboardAPIError.expectedFailure
    }
}

private struct FailingDashboardTodoAPIClient: TodoAPIClientProtocol {
    func listTodos(projectId: UUID?) async throws -> [TodoDTO] {
        throw FailingDashboardAPIError.expectedFailure
    }

    func createTodo(_ payload: TodoCreateRequest) async throws -> TodoDTO {
        throw FailingDashboardAPIError.expectedFailure
    }

    func updateTodo(id: UUID, payload: TodoUpdateRequest) async throws -> TodoDTO {
        throw FailingDashboardAPIError.expectedFailure
    }

    func deleteTodo(id: UUID) async throws {
        throw FailingDashboardAPIError.expectedFailure
    }
}

private actor SuspendedDashboardTodoAPIClient: TodoAPIClientProtocol {
    private let todo: TodoDTO
    private var updateStarted = false
    private var updateCallCount = 0
    private var updateContinuation: CheckedContinuation<Void, Never>?

    init(todo: TodoDTO) {
        self.todo = todo
    }

    func listTodos(projectId: UUID?) async throws -> [TodoDTO] {
        [todo]
    }

    func createTodo(_ payload: TodoCreateRequest) async throws -> TodoDTO {
        todo
    }

    func updateTodo(id: UUID, payload: TodoUpdateRequest) async throws -> TodoDTO {
        updateCallCount += 1
        updateStarted = true
        await withCheckedContinuation { continuation in
            updateContinuation = continuation
        }
        var updated = todo
        updated.isComplete = payload.isComplete ?? updated.isComplete
        return updated
    }

    func deleteTodo(id: UUID) async throws {}

    func waitUntilUpdateStarts() async {
        while !updateStarted {
            await Task.yield()
        }
    }

    func resumeUpdate() {
        updateContinuation?.resume()
        updateContinuation = nil
    }

    func recordedUpdateCallCount() -> Int {
        updateCallCount
    }
}

private struct FailingUpdateDashboardTodoAPIClient: TodoAPIClientProtocol {
    let todo: TodoDTO

    func listTodos(projectId: UUID?) async throws -> [TodoDTO] {
        [todo]
    }

    func createTodo(_ payload: TodoCreateRequest) async throws -> TodoDTO {
        todo
    }

    func updateTodo(id: UUID, payload: TodoUpdateRequest) async throws -> TodoDTO {
        throw FailingTodoCompletionError.expectedFailure
    }

    func deleteTodo(id: UUID) async throws {}
}

private enum FailingTodoCompletionError: LocalizedError {
    case expectedFailure

    var errorDescription: String? {
        "Expected todo completion failure."
    }
}

private struct FailingDashboardProjectAPIClient: ProjectAPIClientProtocol {
    func listProjects(includeArchived: Bool, status: String?, area: String?, tag: String?) async throws -> [ProjectDTO] {
        throw FailingDashboardAPIError.expectedFailure
    }

    func createProject(_ payload: ProjectCreateRequest) async throws -> ProjectDTO {
        throw FailingDashboardAPIError.expectedFailure
    }

    func updateProject(id: UUID, payload: ProjectUpdateRequest) async throws -> ProjectDTO {
        throw FailingDashboardAPIError.expectedFailure
    }

    func deleteProject(id: UUID) async throws {
        throw FailingDashboardAPIError.expectedFailure
    }
}

private enum FailingDashboardAPIError: LocalizedError {
    case expectedFailure

    var errorDescription: String? {
        "Expected dashboard API failure."
    }
}

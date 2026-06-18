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

    private func makeTodo(title: String, isComplete: Bool = false) -> TodoDTO {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        return TodoDTO(
            id: UUID(),
            title: title,
            notes: nil,
            dueDate: nil,
            projectId: nil,
            isComplete: isComplete,
            createdAt: now,
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

    private func makeMemory(title: String, isArchived: Bool = false) -> MemoryDTO {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        return MemoryDTO(
            id: UUID(),
            title: title,
            body: "Body",
            kind: "note",
            sourceUrl: nil,
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
    func listTodos() async throws -> [TodoDTO] {
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

private enum FailingDashboardAPIError: LocalizedError {
    case expectedFailure

    var errorDescription: String? {
        "Expected dashboard API failure."
    }
}

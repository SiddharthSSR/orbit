import XCTest
@testable import Orbit

@MainActor
final class TodayDashboardViewModelTests: XCTestCase {
    func testLoadDashboardLoadsTodosBillsAndMemory() async {
        let viewModel = makeViewModel(
            todos: [makeTodo(title: "Open todo")],
            bills: [makeBill(name: "Rent")],
            memoryItems: [makeMemory(title: "Idea")]
        )

        await viewModel.loadDashboard()

        XCTAssertEqual(viewModel.todos.map(\.title), ["Open todo"])
        XCTAssertEqual(viewModel.bills.map(\.name), ["Rent"])
        XCTAssertEqual(viewModel.memoryItems.map(\.title), ["Idea"])
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

    func testErrorStateIsSetWhenOneAPIFails() async {
        let viewModel = TodayDashboardViewModel(
            todoAPIClient: MockTodoAPIClient(todos: []),
            billAPIClient: FailingDashboardBillAPIClient(),
            memoryAPIClient: MockMemoryAPIClient(memoryItems: [])
        )

        await viewModel.loadDashboard()

        XCTAssertEqual(viewModel.errorMessage, "Expected dashboard API failure.")
        XCTAssertFalse(viewModel.isLoading)
    }

    private func makeViewModel(
        todos: [TodoDTO] = [],
        bills: [BillDTO] = [],
        memoryItems: [MemoryDTO] = []
    ) -> TodayDashboardViewModel {
        TodayDashboardViewModel(
            todoAPIClient: MockTodoAPIClient(todos: todos),
            billAPIClient: MockBillAPIClient(bills: bills),
            memoryAPIClient: MockMemoryAPIClient(memoryItems: memoryItems)
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

private enum FailingDashboardAPIError: LocalizedError {
    case expectedFailure

    var errorDescription: String? {
        "Expected dashboard API failure."
    }
}

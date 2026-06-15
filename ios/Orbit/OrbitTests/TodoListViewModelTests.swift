import XCTest
@testable import Orbit

@MainActor
final class TodoListViewModelTests: XCTestCase {
    func testLoadTodosLoadsMockTodos() async {
        let client = MockTodoAPIClient(todos: [
            makeTodo(title: "Plan day"),
            makeTodo(title: "Review bills", isComplete: true)
        ])
        let viewModel = TodoListViewModel(apiClient: client)

        await viewModel.loadTodos()

        XCTAssertEqual(viewModel.todos.map(\.title), ["Plan day", "Review bills"])
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testCreateTodoAddsTodo() async {
        let viewModel = TodoListViewModel(apiClient: MockTodoAPIClient(todos: []))

        await viewModel.createTodo(title: " Capture receipt ")

        XCTAssertEqual(viewModel.todos.count, 1)
        XCTAssertEqual(viewModel.todos.first?.title, "Capture receipt")
        XCTAssertEqual(viewModel.todos.first?.isComplete, false)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testCreateTodoIgnoresEmptyTitle() async {
        let viewModel = TodoListViewModel(apiClient: MockTodoAPIClient(todos: []))

        await viewModel.createTodo(title: "   \n\t   ")

        XCTAssertTrue(viewModel.todos.isEmpty)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testToggleTodoCompleteFlipsCompletionState() async {
        let todo = makeTodo(title: "Send update")
        let viewModel = TodoListViewModel(apiClient: MockTodoAPIClient(todos: [todo]))

        await viewModel.loadTodos()
        await viewModel.toggleTodoComplete(todo: todo)

        XCTAssertEqual(viewModel.todos.first?.id, todo.id)
        XCTAssertEqual(viewModel.todos.first?.isComplete, true)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testDeleteTodoRemovesTodo() async {
        let todo = makeTodo(title: "Archive note")
        let viewModel = TodoListViewModel(apiClient: MockTodoAPIClient(todos: [todo]))

        await viewModel.loadTodos()
        await viewModel.deleteTodo(todo: todo)

        XCTAssertTrue(viewModel.todos.isEmpty)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testErrorStateIsSetWhenAPIClientThrows() async {
        let viewModel = TodoListViewModel(apiClient: FailingTodoAPIClient())

        await viewModel.loadTodos()

        XCTAssertEqual(viewModel.errorMessage, "Expected todo API failure.")
        XCTAssertFalse(viewModel.isLoading)
    }

    private func makeTodo(
        title: String,
        notes: String? = nil,
        dueDate: Date? = nil,
        projectId: UUID? = nil,
        isComplete: Bool = false
    ) -> TodoDTO {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        return TodoDTO(
            id: UUID(),
            title: title,
            notes: notes,
            dueDate: dueDate,
            projectId: projectId,
            isComplete: isComplete,
            createdAt: now,
            updatedAt: now
        )
    }
}

private struct FailingTodoAPIClient: TodoAPIClientProtocol {
    func listTodos() async throws -> [TodoDTO] {
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

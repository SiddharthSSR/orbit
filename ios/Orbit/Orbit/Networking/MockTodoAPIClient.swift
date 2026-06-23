import Foundation

actor MockTodoAPIClient: TodoAPIClientProtocol {
    private var todos: [TodoDTO]
    private var createRequests: [TodoCreateRequest] = []

    init(todos: [TodoDTO] = MockTodoAPIClient.previewTodos) {
        self.todos = todos
    }

    func recordedCreateRequests() -> [TodoCreateRequest] {
        createRequests
    }

    func listTodos(projectId: UUID? = nil) async throws -> [TodoDTO] {
        if let projectId {
            return todos.filter { $0.projectId == projectId }
        }
        return todos
    }

    func createTodo(_ payload: TodoCreateRequest) async throws -> TodoDTO {
        createRequests.append(payload)
        let now = Date()
        let todo = TodoDTO(
            id: UUID(),
            title: payload.title,
            notes: payload.notes,
            dueDate: payload.dueDate,
            projectId: payload.projectId,
            isComplete: payload.isComplete,
            createdAt: now,
            updatedAt: now
        )
        todos.insert(todo, at: 0)
        return todo
    }

    func updateTodo(id: UUID, payload: TodoUpdateRequest) async throws -> TodoDTO {
        guard let index = todos.firstIndex(where: { $0.id == id }) else {
            throw OrbitAPIError.requestFailed(statusCode: 404, message: "Todo not found")
        }

        var todo = todos[index]
        if let title = payload.title {
            todo.title = title
        }
        if let notes = payload.notes {
            todo.notes = notes
        }
        if let dueDate = payload.dueDate {
            todo.dueDate = dueDate
        }
        if let projectId = payload.projectId {
            todo.projectId = projectId
        }
        if let isComplete = payload.isComplete {
            todo.isComplete = isComplete
        }
        todo.updatedAt = Date()

        todos[index] = todo
        return todo
    }

    func deleteTodo(id: UUID) async throws {
        todos.removeAll { $0.id == id }
    }

    private static let previewTodos: [TodoDTO] = [
        TodoDTO(
            id: UUID(),
            title: "Draft project brief",
            notes: "Outline the next Orbit planning slice",
            dueDate: Date().addingTimeInterval(86_400),
            projectId: MockOrbitFixtureIDs.orbitProjectID,
            isComplete: true,
            createdAt: Date(),
            updatedAt: Date()
        ),
        TodoDTO(
            id: UUID(),
            title: "Review today plan",
            notes: nil,
            dueDate: Calendar.current.startOfDay(for: Date()),
            projectId: nil,
            isComplete: false,
            createdAt: Date(),
            updatedAt: Date()
        ),
        TodoDTO(
            id: UUID(),
            title: "Pay internet bill",
            notes: "Due this week",
            dueDate: Date().addingTimeInterval(86_400),
            projectId: nil,
            isComplete: true,
            createdAt: Date(),
            updatedAt: Date()
        )
    ]
}

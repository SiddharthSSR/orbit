import Foundation

@MainActor
final class TodoListViewModel: ObservableObject {
    @Published private(set) var todos: [TodoDTO] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let apiClient: OrbitAPIClient

    init(apiClient: OrbitAPIClient = OrbitAPIClient()) {
        self.apiClient = apiClient
    }

    func loadTodos() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            todos = try await apiClient.listTodos()
        } catch {
            errorMessage = readableMessage(for: error)
        }
    }

    func createTodo(title: String) async {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }

        errorMessage = nil
        do {
            let todo = try await apiClient.createTodo(TodoCreateRequest(title: trimmedTitle))
            todos.insert(todo, at: 0)
        } catch {
            errorMessage = readableMessage(for: error)
        }
    }

    func toggleTodoComplete(todo: TodoDTO) async {
        errorMessage = nil
        do {
            let updatedTodo = try await apiClient.updateTodo(
                id: todo.id,
                payload: TodoUpdateRequest(isComplete: !todo.isComplete)
            )
            replace(updatedTodo)
        } catch {
            errorMessage = readableMessage(for: error)
        }
    }

    func deleteTodo(todo: TodoDTO) async {
        errorMessage = nil
        do {
            try await apiClient.deleteTodo(id: todo.id)
            todos.removeAll { $0.id == todo.id }
        } catch {
            errorMessage = readableMessage(for: error)
        }
    }

    private func replace(_ todo: TodoDTO) {
        guard let index = todos.firstIndex(where: { $0.id == todo.id }) else {
            todos.insert(todo, at: 0)
            return
        }
        todos[index] = todo
    }

    private func readableMessage(for error: Error) -> String {
        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription {
            return description
        }
        return error.localizedDescription
    }
}


import SwiftUI

struct TodayScreen: View {
    @StateObject private var todoViewModel = TodoListViewModel()
    @State private var newTodoTitle = ""

    private let moodLog = SampleData.moodLogs.first

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                OrbitCard {
                    Label("Daily Plan", systemImage: "calendar")
                        .font(.headline)
                    Text("Start with the most important work, then clear small admin tasks.")
                        .foregroundStyle(.secondary)
                }

                OrbitCard {
                    Label("Mood Check-in", systemImage: "heart")
                        .font(.headline)
                    if let moodLog {
                        Text("\(moodLog.mood) · Energy \(moodLog.energy)/5")
                            .font(.subheadline)
                        Text(moodLog.notes)
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Today")
                        .font(.headline)

                    HStack(spacing: 8) {
                        TextField("Add a todo", text: $newTodoTitle)
                            .textFieldStyle(.roundedBorder)
                            .submitLabel(.done)
                            .onSubmit {
                                createTodo()
                            }

                        Button {
                            createTodo()
                        } label: {
                            Image(systemName: "plus")
                                .frame(width: 32, height: 32)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(newTodoTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityLabel("Add todo")
                    }

                    if todoViewModel.isLoading {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Loading todos")
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 8)
                    } else if let errorMessage = todoViewModel.errorMessage {
                        OrbitCard {
                            Label("Could not load todos", systemImage: "exclamationmark.triangle")
                                .font(.headline)
                            Text(errorMessage)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Button {
                                Task {
                                    await todoViewModel.loadTodos()
                                }
                            } label: {
                                Label("Retry", systemImage: "arrow.clockwise")
                            }
                            .buttonStyle(.bordered)
                        }
                    } else if todoViewModel.todos.isEmpty {
                        EmptyStateView(
                            title: "No todos yet",
                            message: "Add a task to start planning your day.",
                            systemImage: "checklist"
                        )
                        .frame(minHeight: 180)
                    } else {
                        ForEach(todoViewModel.todos) { todo in
                            TodoRow(todo: todo) {
                                Task {
                                    await todoViewModel.toggleTodoComplete(todo: todo)
                                }
                            } onDelete: {
                                Task {
                                    await todoViewModel.deleteTodo(todo: todo)
                                }
                            }
                        }
                    }
                }
                .padding(.top, 4)
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .task {
            await todoViewModel.loadTodos()
        }
    }

    private func createTodo() {
        let title = newTodoTitle
        newTodoTitle = ""
        Task {
            await todoViewModel.createTodo(title: title)
        }
    }
}

private struct TodoRow: View {
    let todo: TodoDTO
    let onToggle: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onToggle) {
                Image(systemName: todo.isComplete ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(todo.isComplete ? .green : .secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(todo.isComplete ? "Mark incomplete" : "Mark complete")

            VStack(alignment: .leading, spacing: 4) {
                Text(todo.title)
                    .strikethrough(todo.isComplete)
                    .foregroundStyle(todo.isComplete ? .secondary : .primary)
                if let dueDate = todo.dueDate {
                    Text(dueDate, style: .date)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Delete todo")
        }
        .padding(.vertical, 8)
    }
}

struct TodayScreen_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            TodayScreen()
                .navigationTitle("Today")
        }
    }
}

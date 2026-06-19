import Foundation

enum TodoUrgency: Equatable {
    case overdue
    case today
    case tomorrow
    case upcoming(Date)

    static func resolve(
        dueDate: Date?,
        relativeTo now: Date = .now,
        calendar: Calendar = .current
    ) -> TodoUrgency? {
        guard let dueDate else { return nil }

        let today = calendar.startOfDay(for: now)
        let dueDay = calendar.startOfDay(for: dueDate)

        if dueDay < today {
            return .overdue
        }
        if dueDay == today {
            return .today
        }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: today),
           dueDay == tomorrow {
            return .tomorrow
        }
        return .upcoming(dueDate)
    }

    var label: String {
        switch self {
        case .overdue:
            "Overdue"
        case .today:
            "Due today"
        case .tomorrow:
            "Due tomorrow"
        case let .upcoming(date):
            "Due \(date.formatted(date: .abbreviated, time: .omitted))"
        }
    }
}

@MainActor
final class TodayDashboardViewModel: ObservableObject {
    @Published private(set) var todos: [TodoDTO] = []
    @Published private(set) var bills: [BillDTO] = []
    @Published private(set) var memoryItems: [MemoryDTO] = []
    @Published private(set) var latestMood: MoodDTO?
    @Published private(set) var isLoading = false
    @Published private(set) var completingTodoIDs: Set<UUID> = []
    @Published private(set) var todoCompletionErrorMessage: String?
    @Published var errorMessage: String?

    private let todoAPIClient: any TodoAPIClientProtocol
    private let billAPIClient: any BillAPIClientProtocol
    private let memoryAPIClient: any MemoryAPIClientProtocol
    private let moodAPIClient: any MoodAPIClientProtocol
    private let notificationCenter: NotificationCenter

    var openTodos: [TodoDTO] {
        displayedOpenTodos()
    }

    func displayedOpenTodos(highlighting highlightedTodoID: UUID? = nil) -> [TodoDTO] {
        Array(
            todos
                .filter { !$0.isComplete }
                .sorted { lhs, rhs in
                    if lhs.id == highlightedTodoID, rhs.id != highlightedTodoID {
                        return true
                    }
                    if rhs.id == highlightedTodoID, lhs.id != highlightedTodoID {
                        return false
                    }

                    switch (lhs.dueDate, rhs.dueDate) {
                    case let (lhsDue?, rhsDue?) where lhsDue != rhsDue:
                        return lhsDue < rhsDue
                    case (_?, nil):
                        return true
                    case (nil, _?):
                        return false
                    default:
                        break
                    }

                    if lhs.createdAt != rhs.createdAt {
                        return lhs.createdAt > rhs.createdAt
                    }
                    return lhs.id.uuidString < rhs.id.uuidString
                }
                .prefix(5)
        )
    }

    var unpaidBills: [BillDTO] {
        Array(bills.filter { !$0.isPaid }.prefix(5))
    }

    var recentMemoryItems: [MemoryDTO] {
        Array(memoryItems.filter { !$0.isArchived }.prefix(5))
    }

    var openTodoCount: Int {
        todos.filter { !$0.isComplete }.count
    }

    var unpaidBillCount: Int {
        bills.filter { !$0.isPaid }.count
    }

    var recentMemoryCount: Int {
        memoryItems.filter { !$0.isArchived }.count
    }

    func isCompletingTodo(id: UUID) -> Bool {
        completingTodoIDs.contains(id)
    }

    init(
        todoAPIClient: any TodoAPIClientProtocol = OrbitAPIClient(),
        billAPIClient: any BillAPIClientProtocol = OrbitAPIClient(),
        memoryAPIClient: any MemoryAPIClientProtocol = OrbitAPIClient(),
        moodAPIClient: any MoodAPIClientProtocol = OrbitAPIClient(),
        notificationCenter: NotificationCenter = .default
    ) {
        self.todoAPIClient = todoAPIClient
        self.billAPIClient = billAPIClient
        self.memoryAPIClient = memoryAPIClient
        self.moodAPIClient = moodAPIClient
        self.notificationCenter = notificationCenter
    }

    func loadDashboard(showsLoading: Bool = true) async {
        if showsLoading {
            isLoading = true
        }
        errorMessage = nil
        defer { isLoading = false }

        do {
            let loadedTodos = try await todoAPIClient.listTodos()
            let loadedBills = try await billAPIClient.listBills()
            let loadedMemory = try await memoryAPIClient.listMemory(
                includeArchived: false,
                kind: nil,
                tag: nil
            )
            let loadedMoods = try await moodAPIClient.listMoods(limit: 1, fromDate: nil, toDate: nil)

            todos = loadedTodos
            bills = loadedBills
            memoryItems = loadedMemory
            latestMood = loadedMoods.first
        } catch {
            errorMessage = readableMessage(for: error)
        }
    }

    func createMood(mood: String, energy: Int, notes: String? = nil) async {
        let trimmedMood = mood.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMood.isEmpty, 1...5 ~= energy else { return }

        let trimmedNotes = notes?.trimmingCharacters(in: .whitespacesAndNewlines)
        errorMessage = nil
        do {
            latestMood = try await moodAPIClient.createMood(
                MoodCreateRequest(
                    mood: trimmedMood,
                    energy: energy,
                    notes: trimmedNotes?.isEmpty == true ? nil : trimmedNotes,
                    checkInDate: nil
                )
            )
        } catch {
            errorMessage = readableMessage(for: error)
        }
    }

    func toggleTodoComplete(todo: TodoDTO) async {
        guard completingTodoIDs.insert(todo.id).inserted else { return }
        todoCompletionErrorMessage = nil
        defer { completingTodoIDs.remove(todo.id) }

        do {
            let updatedTodo = try await todoAPIClient.updateTodo(
                id: todo.id,
                payload: TodoUpdateRequest(isComplete: !todo.isComplete)
            )
            replace(updatedTodo)
            OrbitRefreshCenter.postTodoDidChange(on: notificationCenter)
        } catch {
            todoCompletionErrorMessage = readableMessage(for: error)
        }
    }

    func toggleBillPaid(bill: BillDTO) async {
        errorMessage = nil
        do {
            let updatedBill = try await billAPIClient.updateBill(
                id: bill.id,
                payload: BillUpdateRequest(isPaid: !bill.isPaid)
            )
            replace(updatedBill)
            OrbitRefreshCenter.postBillsDidChange(on: notificationCenter)
        } catch {
            errorMessage = readableMessage(for: error)
        }
    }

    func archiveMemory(memory: MemoryDTO) async {
        errorMessage = nil
        do {
            let archivedMemory = try await memoryAPIClient.updateMemory(
                id: memory.id,
                payload: MemoryUpdateRequest(isArchived: true)
            )
            replace(archivedMemory)
            OrbitRefreshCenter.postMemoryDidChange(on: notificationCenter)
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

    private func replace(_ bill: BillDTO) {
        guard let index = bills.firstIndex(where: { $0.id == bill.id }) else {
            bills.insert(bill, at: 0)
            return
        }
        bills[index] = bill
    }

    private func replace(_ memory: MemoryDTO) {
        guard let index = memoryItems.firstIndex(where: { $0.id == memory.id }) else {
            if !memory.isArchived {
                memoryItems.insert(memory, at: 0)
            }
            return
        }
        if memory.isArchived {
            memoryItems.remove(at: index)
        } else {
            memoryItems[index] = memory
        }
    }

    private func readableMessage(for error: Error) -> String {
        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription {
            return description
        }
        return error.localizedDescription
    }
}

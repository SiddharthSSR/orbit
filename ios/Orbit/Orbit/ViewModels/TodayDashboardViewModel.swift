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

struct TodayProjectDigestItem: Identifiable, Equatable {
    let project: ProjectDTO
    let openTodoCount: Int
    let completedTodoCount: Int
    let memoryCount: Int
    let nextDueTodo: TodoDTO?

    var id: UUID { project.id }

    /// True when the project has linked activity but no open linked todos, so the
    /// digest row can show a calm, positive "all caught up" signal instead of a
    /// silent zero. (Items only appear in the digest when they have some linked
    /// activity, so this also covers completed-only and memory-only projects.)
    var isCaughtUp: Bool { openTodoCount == 0 }

    static func derive(
        projects: [ProjectDTO],
        todos: [TodoDTO],
        memoryItems: [MemoryDTO],
        limit: Int = 4
    ) -> [TodayProjectDigestItem] {
        projects
            .compactMap { project in
                let linkedTodos = todos.filter { $0.projectId == project.id }
                let linkedMemoryItems = memoryItems.filter { $0.projectId == project.id && !$0.isArchived }
                guard !linkedTodos.isEmpty || !linkedMemoryItems.isEmpty else { return nil }

                let openTodos = linkedTodos.filter { !$0.isComplete }
                let completedTodoCount = linkedTodos.filter(\.isComplete).count
                let nextDueTodo = openTodos
                    .filter { $0.dueDate != nil }
                    .sorted(by: todoDueDateSort)
                    .first

                return TodayProjectDigestItem(
                    project: project,
                    openTodoCount: openTodos.count,
                    completedTodoCount: completedTodoCount,
                    memoryCount: linkedMemoryItems.count,
                    nextDueTodo: nextDueTodo
                )
            }
            .sorted(by: digestSort)
            .prefix(limit)
            .map { $0 }
    }

    private static func digestSort(
        lhs: TodayProjectDigestItem,
        rhs: TodayProjectDigestItem
    ) -> Bool {
        switch (lhs.nextDueTodo?.dueDate, rhs.nextDueTodo?.dueDate) {
        case let (lhsDue?, rhsDue?) where lhsDue != rhsDue:
            return lhsDue < rhsDue
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        default:
            break
        }

        if lhs.openTodoCount != rhs.openTodoCount {
            return lhs.openTodoCount > rhs.openTodoCount
        }

        let lhsActivity = latestActivityDate(for: lhs)
        let rhsActivity = latestActivityDate(for: rhs)
        if lhsActivity != rhsActivity {
            return lhsActivity > rhsActivity
        }

        return lhs.project.name.localizedCaseInsensitiveCompare(rhs.project.name) == .orderedAscending
    }

    private static func latestActivityDate(for item: TodayProjectDigestItem) -> Date {
        [item.project.updatedAt, item.nextDueTodo?.updatedAt]
            .compactMap { $0 }
            .max() ?? item.project.updatedAt
    }

    private static func todoDueDateSort(lhs: TodoDTO, rhs: TodoDTO) -> Bool {
        switch (lhs.dueDate, rhs.dueDate) {
        case let (lhsDue?, rhsDue?) where lhsDue != rhsDue:
            return lhsDue < rhsDue
        default:
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    /// Compact, deterministic next-due cue for the digest row, or `nil` when the
    /// project has no open dated todo. Urgency is conveyed in the wording so the
    /// row stays compact:
    /// - Overdue: `Overdue: <title>`
    /// - Due today: `Due today: <title>`
    /// - Later (incl. tomorrow): `Next: <title> · <date>`
    func nextDueCue(
        relativeTo now: Date = .now,
        calendar: Calendar = .current
    ) -> String? {
        guard let todo = nextDueTodo,
              let dueDate = todo.dueDate,
              let urgency = TodoUrgency.resolve(dueDate: dueDate, relativeTo: now, calendar: calendar)
        else { return nil }

        switch urgency {
        case .overdue:
            return "Overdue: \(todo.title)"
        case .today:
            return "Due today: \(todo.title)"
        case .tomorrow, .upcoming:
            return "Next: \(todo.title) · \(dueDate.formatted(date: .abbreviated, time: .omitted))"
        }
    }
}

/// Compact, deterministic glance summary of the project digest, shown in the
/// section header so the digest reads at a glance. Combines the digest project
/// count with either the total open linked todos or a calm "All caught up"
/// signal when no digest project has open todos.
struct TodayProjectDigestSummary: Equatable {
    let projectCount: Int
    let openTodoCount: Int

    /// True when no digest project has an open linked todo, so the header can
    /// echo the same calm signal used by individual caught-up rows.
    var isAllCaughtUp: Bool { openTodoCount == 0 }

    /// Header copy, e.g. `4 projects · 2 open` or `1 project · All caught up`.
    /// Kept terse and free of dynamic dates so it stays stable and testable.
    var label: String {
        let projectPart = projectCount == 1 ? "1 project" : "\(projectCount) projects"
        let activityPart = isAllCaughtUp
            ? "All caught up"
            : (openTodoCount == 1 ? "1 open" : "\(openTodoCount) open")
        return "\(projectPart) · \(activityPart)"
    }

    /// Derives the summary from digest items, or `nil` for an empty digest so the
    /// header stays clean and the existing empty state is preserved.
    static func derive(from items: [TodayProjectDigestItem]) -> TodayProjectDigestSummary? {
        guard !items.isEmpty else { return nil }
        return TodayProjectDigestSummary(
            projectCount: items.count,
            openTodoCount: items.reduce(0) { $0 + $1.openTodoCount }
        )
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
    @Published private(set) var projects: [ProjectDTO] = []
    @Published private(set) var projectLoadErrorMessage: String?
    @Published private(set) var updatingProjectTodoIDs: Set<UUID> = []
    @Published private(set) var todoProjectLinkErrors: [UUID: String] = [:]
    @Published var errorMessage: String?

    private let todoAPIClient: any TodoAPIClientProtocol
    private let billAPIClient: any BillAPIClientProtocol
    private let memoryAPIClient: any MemoryAPIClientProtocol
    private let moodAPIClient: any MoodAPIClientProtocol
    private let projectAPIClient: any ProjectAPIClientProtocol
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

    var projectDigestItems: [TodayProjectDigestItem] {
        TodayProjectDigestItem.derive(
            projects: projects,
            todos: todos,
            memoryItems: memoryItems
        )
    }

    /// Glance summary for the Project Digest section header, or `nil` when the
    /// digest is empty.
    var projectDigestSummary: TodayProjectDigestSummary? {
        TodayProjectDigestSummary.derive(from: projectDigestItems)
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
        projectAPIClient: any ProjectAPIClientProtocol = OrbitAPIClient(),
        notificationCenter: NotificationCenter = .default
    ) {
        self.todoAPIClient = todoAPIClient
        self.billAPIClient = billAPIClient
        self.memoryAPIClient = memoryAPIClient
        self.moodAPIClient = moodAPIClient
        self.projectAPIClient = projectAPIClient
        self.notificationCenter = notificationCenter
    }

    /// Loads non-archived projects used by the per-todo project-link menu. A
    /// failure here is surfaced separately and never blocks the todo list.
    func loadProjects() async {
        projectLoadErrorMessage = nil
        do {
            projects = try await projectAPIClient.listProjects(
                includeArchived: false,
                status: nil,
                area: nil,
                tag: nil
            )
        } catch {
            projectLoadErrorMessage = readableMessage(for: error)
        }
    }

    func projectName(for projectID: UUID?) -> String? {
        guard let projectID else { return nil }
        return projects.first(where: { $0.id == projectID })?.name
    }

    func isUpdatingProject(id: UUID) -> Bool {
        updatingProjectTodoIDs.contains(id)
    }

    /// Assigns, changes, or (with `projectID == nil`) unlinks a todo's project,
    /// then refreshes other surfaces (e.g. Project detail) via the todo change
    /// notification. Todo title/status/due-date are untouched.
    func updateTodoProjectLink(todo: TodoDTO, projectID: UUID?) async {
        guard !updatingProjectTodoIDs.contains(todo.id) else { return }
        var updatingIDs = updatingProjectTodoIDs
        updatingIDs.insert(todo.id)
        updatingProjectTodoIDs = updatingIDs
        todoProjectLinkErrors[todo.id] = nil
        defer {
            var updatedIDs = updatingProjectTodoIDs
            updatedIDs.remove(todo.id)
            updatingProjectTodoIDs = updatedIDs
        }

        do {
            let updatedTodo = try await todoAPIClient.updateTodoProject(
                id: todo.id,
                payload: TodoProjectLinkRequest(projectId: projectID)
            )
            replace(updatedTodo)
            OrbitRefreshCenter.postTodoDidChange(on: notificationCenter)
        } catch {
            todoProjectLinkErrors[todo.id] = readableMessage(for: error)
        }
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
                tag: nil,
                projectId: nil
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

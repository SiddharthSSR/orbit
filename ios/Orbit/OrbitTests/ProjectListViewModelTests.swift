import XCTest
@testable import Orbit

@MainActor
final class ProjectListViewModelTests: XCTestCase {
    func testLoadProjectsLoadsMockProjects() async {
        let viewModel = ProjectListViewModel(apiClient: MockProjectAPIClient(projects: [
            makeProject(name: "Orbit"),
            makeProject(name: "WorldLens", status: "paused")
        ]))

        await viewModel.loadProjects()

        XCTAssertEqual(viewModel.projects.map(\.name), ["Orbit", "WorldLens"])
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testCreateProjectAddsProject() async {
        let viewModel = ProjectListViewModel(apiClient: MockProjectAPIClient(projects: []))

        await viewModel.createProject(
            name: " Orbit ",
            description: " Build second brain. ",
            status: "active",
            area: " orbit ",
            tags: [" ios ", "backend", "ios"]
        )

        XCTAssertEqual(viewModel.projects.count, 1)
        XCTAssertEqual(viewModel.projects.first?.name, "Orbit")
        XCTAssertEqual(viewModel.projects.first?.description, "Build second brain.")
        XCTAssertEqual(viewModel.projects.first?.area, "orbit")
        XCTAssertEqual(viewModel.projects.first?.tags, ["ios", "backend"])
        XCTAssertNil(viewModel.errorMessage)
    }

    func testCreateProjectIgnoresBlankName() async {
        let viewModel = ProjectListViewModel(apiClient: MockProjectAPIClient(projects: []))

        await viewModel.createProject(name: "   ")

        XCTAssertTrue(viewModel.projects.isEmpty)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testUpdateProjectStatusUpdatesStatus() async {
        let project = makeProject(name: "Orbit", status: "active")
        let viewModel = ProjectListViewModel(apiClient: MockProjectAPIClient(projects: [project]))

        await viewModel.loadProjects()
        await viewModel.updateProjectStatus(project: project, status: "paused")

        XCTAssertEqual(viewModel.projects.first?.status, "paused")
        XCTAssertNil(viewModel.errorMessage)
    }

    func testArchiveProjectRemovesArchivedProjectFromDefaultList() async {
        let project = makeProject(name: "Archive me")
        let viewModel = ProjectListViewModel(apiClient: MockProjectAPIClient(projects: [project]))

        await viewModel.loadProjects()
        await viewModel.archiveProject(project: project)

        XCTAssertTrue(viewModel.projects.isEmpty)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testDeleteProjectRemovesProject() async {
        let project = makeProject(name: "Delete me")
        let viewModel = ProjectListViewModel(apiClient: MockProjectAPIClient(projects: [project]))

        await viewModel.loadProjects()
        await viewModel.deleteProject(project: project)

        XCTAssertTrue(viewModel.projects.isEmpty)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testErrorStateIsSetWhenProjectAPIThrows() async {
        let viewModel = ProjectListViewModel(apiClient: FailingProjectAPIClient())

        await viewModel.loadProjects()

        XCTAssertEqual(viewModel.errorMessage, "Expected project API failure.")
        XCTAssertFalse(viewModel.isLoading)
    }

    func testStatusAreaAndTagFiltersLoadMatchingProjects() async {
        let viewModel = ProjectListViewModel(apiClient: MockProjectAPIClient(projects: [
            makeProject(name: "Orbit", status: "active", area: "orbit", tags: ["ios", "backend"]),
            makeProject(name: "Learning", status: "active", area: "learning", tags: ["ai"]),
            makeProject(name: "Paused Orbit", status: "paused", area: "orbit", tags: ["ios"])
        ]))

        await viewModel.setStatusFilter("active")
        await viewModel.setAreaFilter("orbit")
        await viewModel.setTagFilter("ios")

        XCTAssertEqual(viewModel.projects.map(\.name), ["Orbit"])
    }

    func testProjectActivitySummaryCountsAndDerivedFields() {
        let early = Date(timeIntervalSince1970: 1_700_000_000)
        let later = Date(timeIntervalSince1970: 1_700_100_000)
        let soonDue = Date(timeIntervalSince1970: 1_700_050_000)
        let lateDue = Date(timeIntervalSince1970: 1_700_200_000)

        let todos = [
            makeSummaryTodo(title: "Open soon", isComplete: false, dueDate: soonDue),
            makeSummaryTodo(title: "Open later", isComplete: false, dueDate: lateDue),
            makeSummaryTodo(title: "Done task", isComplete: true, dueDate: nil)
        ]
        let memories = [
            makeSummaryMemory(createdAt: early),
            makeSummaryMemory(createdAt: later)
        ]

        let summary = ProjectActivitySummary(todos: todos, memories: memories)

        XCTAssertEqual(summary.linkedTodoCount, 3)
        XCTAssertEqual(summary.linkedMemoryCount, 2)
        XCTAssertEqual(summary.openTodoCount, 2)
        XCTAssertEqual(summary.completedTodoCount, 1)
        XCTAssertEqual(summary.nextDueTodo?.title, "Open soon")
        XCTAssertEqual(summary.lastMemoryCapturedAt, later)
    }

    func testProjectActivitySummaryHandlesEmptyInputs() {
        let summary = ProjectActivitySummary(todos: [], memories: [])

        XCTAssertEqual(summary.linkedTodoCount, 0)
        XCTAssertEqual(summary.linkedMemoryCount, 0)
        XCTAssertEqual(summary.openTodoCount, 0)
        XCTAssertEqual(summary.completedTodoCount, 0)
        XCTAssertNil(summary.nextDueTodo)
        XCTAssertNil(summary.lastMemoryCapturedAt)
    }

    func testProjectActivitySummaryIgnoresCompletedAndUndatedForNextDue() {
        let due = Date(timeIntervalSince1970: 1_700_050_000)
        let todos = [
            makeSummaryTodo(title: "Completed dated", isComplete: true, dueDate: due),
            makeSummaryTodo(title: "Open undated", isComplete: false, dueDate: nil)
        ]

        let summary = ProjectActivitySummary(todos: todos, memories: [])

        XCTAssertNil(summary.nextDueTodo)
    }

    private func makeSummaryTodo(
        title: String,
        isComplete: Bool,
        dueDate: Date?
    ) -> TodoDTO {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        return TodoDTO(
            id: UUID(),
            title: title,
            notes: nil,
            dueDate: dueDate,
            projectId: nil,
            isComplete: isComplete,
            createdAt: now,
            updatedAt: now
        )
    }

    private func makeSummaryMemory(createdAt: Date) -> MemoryDTO {
        MemoryDTO(
            id: UUID(),
            title: "Memory",
            body: "Body",
            kind: "note",
            sourceUrl: nil,
            tags: [],
            isArchived: false,
            createdAt: createdAt,
            updatedAt: createdAt
        )
    }

    private func makeProject(
        name: String,
        status: String = "active",
        area: String? = nil,
        tags: [String] = []
    ) -> ProjectDTO {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        return ProjectDTO(
            id: UUID(),
            name: name,
            description: "Description",
            status: status,
            area: area,
            tags: tags,
            createdAt: now,
            updatedAt: now
        )
    }
}

private struct FailingProjectAPIClient: ProjectAPIClientProtocol {
    func listProjects(includeArchived: Bool, status: String?, area: String?, tag: String?) async throws -> [ProjectDTO] {
        throw FailingProjectAPIError.expectedFailure
    }

    func createProject(_ payload: ProjectCreateRequest) async throws -> ProjectDTO {
        throw FailingProjectAPIError.expectedFailure
    }

    func updateProject(id: UUID, payload: ProjectUpdateRequest) async throws -> ProjectDTO {
        throw FailingProjectAPIError.expectedFailure
    }

    func deleteProject(id: UUID) async throws {
        throw FailingProjectAPIError.expectedFailure
    }
}

private enum FailingProjectAPIError: LocalizedError {
    case expectedFailure

    var errorDescription: String? {
        "Expected project API failure."
    }
}

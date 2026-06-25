import XCTest
@testable import Orbit

@MainActor
final class MemoryListViewModelTests: XCTestCase {
    func testLoadMemoryLoadsMockMemory() async {
        let client = MockMemoryAPIClient(memoryItems: [
            makeMemory(title: "AI article", kind: "link"),
            makeMemory(title: "App idea", kind: "idea")
        ])
        let viewModel = MemoryListViewModel(apiClient: client)

        await viewModel.loadMemory()

        XCTAssertEqual(viewModel.memoryItems.map(\.title), ["AI article", "App idea"])
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testLoadProjectsLoadsNonArchivedProjects() async {
        let active = makeProject(name: "Orbit")
        let archived = makeProject(name: "Old project", status: "archived")
        let viewModel = MemoryListViewModel(
            apiClient: MockMemoryAPIClient(memoryItems: []),
            projectAPIClient: MockProjectAPIClient(projects: [active, archived])
        )

        await viewModel.loadProjects()

        XCTAssertEqual(viewModel.projects.map(\.name), ["Orbit"])
        XCTAssertNil(viewModel.projectLoadErrorMessage)
    }

    func testProjectLoadingFailureDoesNotBreakLoadedMemory() async {
        let viewModel = MemoryListViewModel(
            apiClient: MockMemoryAPIClient(memoryItems: [makeMemory(title: "Keep visible")]),
            projectAPIClient: FailingInboxProjectAPIClient()
        )

        await viewModel.loadMemory()
        await viewModel.loadProjects()

        XCTAssertEqual(viewModel.memoryItems.map(\.title), ["Keep visible"])
        XCTAssertEqual(viewModel.projectLoadErrorMessage, "Expected project API failure.")
        XCTAssertNil(viewModel.errorMessage)
    }

    func testCreateMemoryAddsItem() async {
        let viewModel = MemoryListViewModel(apiClient: MockMemoryAPIClient(memoryItems: []))

        await viewModel.createMemory(
            title: " iPhone app idea ",
            body: " Build one capture field. ",
            kind: "idea",
            sourceURL: " ",
            tags: [" orbit ", "ideas", "ideas"]
        )

        XCTAssertEqual(viewModel.memoryItems.count, 1)
        XCTAssertEqual(viewModel.memoryItems.first?.title, "iPhone app idea")
        XCTAssertEqual(viewModel.memoryItems.first?.body, "Build one capture field.")
        XCTAssertEqual(viewModel.memoryItems.first?.kind, "idea")
        XCTAssertEqual(viewModel.memoryItems.first?.tags, ["orbit", "ideas"])
        XCTAssertNil(viewModel.memoryItems.first?.sourceUrl)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testCreateMemoryIgnoresBlankTitleOrBody() async {
        let viewModel = MemoryListViewModel(apiClient: MockMemoryAPIClient(memoryItems: []))

        await viewModel.createMemory(title: "   ", body: "Body")
        await viewModel.createMemory(title: "Title", body: " \n\t ")

        XCTAssertTrue(viewModel.memoryItems.isEmpty)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testArchiveMemorySetsArchivedAndRemovesFromDefaultList() async {
        let memory = makeMemory(title: "Archive me")
        let viewModel = MemoryListViewModel(apiClient: MockMemoryAPIClient(memoryItems: [memory]))

        await viewModel.loadMemory()
        await viewModel.archiveMemory(memory: memory)

        XCTAssertTrue(viewModel.memoryItems.isEmpty)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testUpdateProjectLinkUpdatesLocalMemoryAndCanUnlink() async {
        let center = NotificationCenter()
        let project = makeProject(name: "Orbit")
        let memory = makeMemory(title: "Project note")
        let viewModel = MemoryListViewModel(
            apiClient: MockMemoryAPIClient(memoryItems: [memory]),
            projectAPIClient: MockProjectAPIClient(projects: [project]),
            notificationCenter: center
        )
        await viewModel.loadMemory()
        await viewModel.loadProjects()

        let linkEvent = XCTNSNotificationExpectation(
            name: .orbitMemoryDidChange,
            object: nil,
            notificationCenter: center
        )
        await viewModel.updateProjectLink(memory: memory, projectID: project.id)
        await fulfillment(of: [linkEvent], timeout: 0.5)

        XCTAssertEqual(viewModel.memoryItems.first?.projectId, project.id)
        XCTAssertEqual(viewModel.projectName(for: project.id), "Orbit")
        XCTAssertNil(viewModel.projectLinkErrorMessages[memory.id])

        let linkedMemory = try? XCTUnwrap(viewModel.memoryItems.first)
        if let linkedMemory {
            let unlinkEvent = XCTNSNotificationExpectation(
                name: .orbitMemoryDidChange,
                object: nil,
                notificationCenter: center
            )
            await viewModel.updateProjectLink(memory: linkedMemory, projectID: nil)
            await fulfillment(of: [unlinkEvent], timeout: 0.5)
        }

        XCTAssertNil(viewModel.memoryItems.first?.projectId)
    }

    func testFailedProjectLinkKeepsMemoryAndShowsRowError() async {
        let memory = makeMemory(title: "Keep visible")
        let viewModel = MemoryListViewModel(
            apiClient: FailingProjectLinkMemoryAPIClient(memory: memory)
        )
        await viewModel.loadMemory()

        await viewModel.updateProjectLink(memory: memory, projectID: UUID())

        XCTAssertEqual(viewModel.memoryItems.map(\.title), ["Keep visible"])
        XCTAssertNil(viewModel.memoryItems.first?.projectId)
        XCTAssertEqual(
            viewModel.projectLinkErrorMessages[memory.id],
            "Expected project link failure."
        )
        XCTAssertNil(viewModel.errorMessage)
    }

    func testDeleteMemoryRemovesItem() async {
        let memory = makeMemory(title: "Delete me")
        let viewModel = MemoryListViewModel(apiClient: MockMemoryAPIClient(memoryItems: [memory]))

        await viewModel.loadMemory()
        await viewModel.deleteMemory(memory: memory)

        XCTAssertTrue(viewModel.memoryItems.isEmpty)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testErrorStateIsSetWhenMemoryAPIThrows() async {
        let viewModel = MemoryListViewModel(apiClient: FailingMemoryAPIClient())

        await viewModel.loadMemory()

        XCTAssertEqual(viewModel.errorMessage, "Expected memory API failure.")
        XCTAssertFalse(viewModel.isLoading)
    }

    func testKindAndTagFiltersLoadMatchingMemory() async {
        let client = MockMemoryAPIClient(memoryItems: [
            makeMemory(title: "AI article", kind: "link", tags: ["ai", "read-later"]),
            makeMemory(title: "Project note", kind: "project_update", tags: ["worldlens"])
        ])
        let viewModel = MemoryListViewModel(apiClient: client)

        await viewModel.setKindFilter("link")
        await viewModel.setTagFilter("ai")

        XCTAssertEqual(viewModel.memoryItems.map(\.title), ["AI article"])
    }

    func testMockMemoryClientFiltersByProjectId() async throws {
        let project = UUID()
        let client = MockMemoryAPIClient(memoryItems: [
            makeMemory(title: "Project note", projectId: project),
            makeMemory(title: "Other project note", projectId: UUID()),
            makeMemory(title: "Unlinked note")
        ])

        let linkedMemory = try await client.listMemory(
            includeArchived: false,
            kind: nil,
            tag: nil,
            projectId: project
        )

        XCTAssertEqual(linkedMemory.map(\.title), ["Project note"])
    }

    func testCreateMemoryEmitsMemoryRefreshEvent() async {
        let center = NotificationCenter()
        let viewModel = MemoryListViewModel(
            apiClient: MockMemoryAPIClient(memoryItems: []),
            notificationCenter: center
        )
        let event = XCTNSNotificationExpectation(name: .orbitMemoryDidChange, object: nil, notificationCenter: center)

        await viewModel.createMemory(title: "Quiet cafes", body: "Near work")

        await fulfillment(of: [event], timeout: 0.5)
    }

    func testArchiveAndDeleteMemoryEmitMemoryRefreshEvents() async {
        let center = NotificationCenter()
        let memory = makeMemory(title: "Archive me")
        let viewModel = MemoryListViewModel(
            apiClient: MockMemoryAPIClient(memoryItems: [memory]),
            notificationCenter: center
        )
        await viewModel.loadMemory()

        let archiveEvent = XCTNSNotificationExpectation(name: .orbitMemoryDidChange, object: nil, notificationCenter: center)
        await viewModel.archiveMemory(memory: memory)
        await fulfillment(of: [archiveEvent], timeout: 0.5)

        let deleteEvent = XCTNSNotificationExpectation(name: .orbitMemoryDidChange, object: nil, notificationCenter: center)
        await viewModel.deleteMemory(memory: memory)
        await fulfillment(of: [deleteEvent], timeout: 0.5)
    }

    func testFailedMemoryMutationDoesNotEmitRefreshEvent() async {
        let center = NotificationCenter()
        let viewModel = MemoryListViewModel(
            apiClient: FailingMemoryAPIClient(),
            notificationCenter: center
        )
        let event = XCTNSNotificationExpectation(name: .orbitMemoryDidChange, object: nil, notificationCenter: center)
        event.isInverted = true

        await viewModel.createMemory(title: "Will fail", body: "Body")

        await fulfillment(of: [event], timeout: 0.3)
    }

    func testBlankMemoryDoesNotEmitRefreshEvent() async {
        let center = NotificationCenter()
        let viewModel = MemoryListViewModel(
            apiClient: MockMemoryAPIClient(memoryItems: []),
            notificationCenter: center
        )
        let event = XCTNSNotificationExpectation(name: .orbitMemoryDidChange, object: nil, notificationCenter: center)
        event.isInverted = true

        await viewModel.createMemory(title: "   ", body: "   ")

        await fulfillment(of: [event], timeout: 0.3)
    }

    func testCaptureQualityNeedsReviewForBareCapture() {
        let memory = makeMemory(title: "Quick thought")
        let quality = MemoryCaptureQuality(memory: memory)

        XCTAssertFalse(quality.isLinkedToProject)
        XCTAssertFalse(quality.hasTags)
        XCTAssertFalse(quality.hasSource)
        XCTAssertTrue(quality.needsReview)
    }

    func testCaptureQualityDoesNotNeedReviewWhenTagged() {
        let quality = MemoryCaptureQuality(memory: makeMemory(title: "Idea", tags: ["orbit"]))

        XCTAssertTrue(quality.hasTags)
        XCTAssertFalse(quality.needsReview)
    }

    func testCaptureQualityDoesNotNeedReviewWhenLinkedToProject() {
        let quality = MemoryCaptureQuality(memory: makeMemory(title: "Note", projectId: UUID()))

        XCTAssertTrue(quality.isLinkedToProject)
        XCTAssertFalse(quality.needsReview)
    }

    func testCaptureQualityDoesNotNeedReviewWhenSourcePresent() {
        let quality = MemoryCaptureQuality(
            memory: makeMemory(title: "Saved link", sourceUrl: "https://example.com")
        )

        XCTAssertTrue(quality.hasSource)
        XCTAssertFalse(quality.needsReview)
    }

    func testCaptureQualityTreatsEmptySourceStringAsNoSource() {
        let quality = MemoryCaptureQuality(memory: makeMemory(title: "Empty source", sourceUrl: ""))

        XCTAssertFalse(quality.hasSource)
        XCTAssertTrue(quality.needsReview)
    }

    func testInboxFilterAllReturnsEveryMemory() async {
        let viewModel = await loadedFilterViewModel()

        viewModel.activeInboxFilter = .all

        XCTAssertEqual(
            viewModel.filteredMemoryItems.map(\.title),
            ["Bare", "Linked", "Sourced", "Tagged"]
        )
    }

    func testInboxFilterNeedsReviewReturnsBareCaptures() async {
        let viewModel = await loadedFilterViewModel()

        viewModel.activeInboxFilter = .needsReview

        XCTAssertEqual(viewModel.filteredMemoryItems.map(\.title), ["Bare"])
    }

    func testInboxFilterLinkedReturnsProjectLinkedMemories() async {
        let viewModel = await loadedFilterViewModel()

        viewModel.activeInboxFilter = .linked

        XCTAssertEqual(viewModel.filteredMemoryItems.map(\.title), ["Linked"])
    }

    func testInboxFilterHasSourceReturnsMemoriesWithSource() async {
        let viewModel = await loadedFilterViewModel()

        viewModel.activeInboxFilter = .hasSource

        XCTAssertEqual(viewModel.filteredMemoryItems.map(\.title), ["Sourced"])
    }

    func testInboxFilterEmptyResultWhenNoMemoryMatches() async {
        let viewModel = MemoryListViewModel(
            apiClient: MockMemoryAPIClient(memoryItems: [makeMemory(title: "Tagged", tags: ["orbit"])])
        )
        await viewModel.loadMemory()

        viewModel.activeInboxFilter = .needsReview

        XCTAssertTrue(viewModel.filteredMemoryItems.isEmpty)
        XCTAssertFalse(viewModel.memoryItems.isEmpty)
    }

    /// View model seeded with one memory per capture-quality state, in a fixed
    /// order, so filter assertions stay deterministic.
    private func loadedFilterViewModel() async -> MemoryListViewModel {
        let viewModel = MemoryListViewModel(
            apiClient: MockMemoryAPIClient(memoryItems: [
                makeMemory(title: "Bare"),
                makeMemory(title: "Linked", projectId: UUID()),
                makeMemory(title: "Sourced", sourceUrl: "https://example.com"),
                makeMemory(title: "Tagged", tags: ["orbit"])
            ])
        )
        await viewModel.loadMemory()
        return viewModel
    }

    private func makeMemory(
        title: String,
        body: String = "Body",
        kind: String = "note",
        tags: [String] = [],
        sourceUrl: String? = nil,
        projectId: UUID? = nil,
        isArchived: Bool = false
    ) -> MemoryDTO {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        return MemoryDTO(
            id: UUID(),
            title: title,
            body: body,
            kind: kind,
            sourceUrl: sourceUrl,
            projectId: projectId,
            tags: tags,
            isArchived: isArchived,
            createdAt: now,
            updatedAt: now
        )
    }

    private func makeProject(name: String, status: String = "active") -> ProjectDTO {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        return ProjectDTO(
            id: UUID(),
            name: name,
            description: nil,
            status: status,
            area: nil,
            tags: [],
            createdAt: now,
            updatedAt: now
        )
    }
}

private struct FailingMemoryAPIClient: MemoryAPIClientProtocol {
    func listMemory(includeArchived: Bool, kind: String?, tag: String?, projectId: UUID?) async throws -> [MemoryDTO] {
        throw FailingMemoryAPIError.expectedFailure
    }

    func createMemory(_ payload: MemoryCreateRequest) async throws -> MemoryDTO {
        throw FailingMemoryAPIError.expectedFailure
    }

    func updateMemory(id: UUID, payload: MemoryUpdateRequest) async throws -> MemoryDTO {
        throw FailingMemoryAPIError.expectedFailure
    }

    func updateMemoryProject(id: UUID, payload: MemoryProjectLinkRequest) async throws -> MemoryDTO {
        throw FailingMemoryAPIError.expectedFailure
    }

    func deleteMemory(id: UUID) async throws {
        throw FailingMemoryAPIError.expectedFailure
    }
}

private struct FailingProjectLinkMemoryAPIClient: MemoryAPIClientProtocol {
    let memory: MemoryDTO

    func listMemory(includeArchived: Bool, kind: String?, tag: String?, projectId: UUID?) async throws -> [MemoryDTO] {
        [memory]
    }

    func createMemory(_ payload: MemoryCreateRequest) async throws -> MemoryDTO {
        memory
    }

    func updateMemory(id: UUID, payload: MemoryUpdateRequest) async throws -> MemoryDTO {
        memory
    }

    func updateMemoryProject(id: UUID, payload: MemoryProjectLinkRequest) async throws -> MemoryDTO {
        throw FailingProjectLinkMemoryAPIError.expectedFailure
    }

    func deleteMemory(id: UUID) async throws {}
}

private enum FailingProjectLinkMemoryAPIError: LocalizedError {
    case expectedFailure

    var errorDescription: String? {
        "Expected project link failure."
    }
}

private struct FailingInboxProjectAPIClient: ProjectAPIClientProtocol {
    func listProjects(
        includeArchived: Bool,
        status: String?,
        area: String?,
        tag: String?
    ) async throws -> [ProjectDTO] {
        throw FailingInboxProjectAPIError.expectedFailure
    }

    func createProject(_ payload: ProjectCreateRequest) async throws -> ProjectDTO {
        throw FailingInboxProjectAPIError.expectedFailure
    }

    func updateProject(id: UUID, payload: ProjectUpdateRequest) async throws -> ProjectDTO {
        throw FailingInboxProjectAPIError.expectedFailure
    }

    func deleteProject(id: UUID) async throws {
        throw FailingInboxProjectAPIError.expectedFailure
    }
}

private enum FailingInboxProjectAPIError: LocalizedError {
    case expectedFailure

    var errorDescription: String? {
        "Expected project API failure."
    }
}

private enum FailingMemoryAPIError: LocalizedError {
    case expectedFailure

    var errorDescription: String? {
        "Expected memory API failure."
    }
}

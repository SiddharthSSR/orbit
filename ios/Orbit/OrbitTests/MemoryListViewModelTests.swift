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

    private func makeMemory(
        title: String,
        body: String = "Body",
        kind: String = "note",
        tags: [String] = [],
        isArchived: Bool = false
    ) -> MemoryDTO {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        return MemoryDTO(
            id: UUID(),
            title: title,
            body: body,
            kind: kind,
            sourceUrl: nil,
            tags: tags,
            isArchived: isArchived,
            createdAt: now,
            updatedAt: now
        )
    }
}

private struct FailingMemoryAPIClient: MemoryAPIClientProtocol {
    func listMemory(includeArchived: Bool, kind: String?, tag: String?) async throws -> [MemoryDTO] {
        throw FailingMemoryAPIError.expectedFailure
    }

    func createMemory(_ payload: MemoryCreateRequest) async throws -> MemoryDTO {
        throw FailingMemoryAPIError.expectedFailure
    }

    func updateMemory(id: UUID, payload: MemoryUpdateRequest) async throws -> MemoryDTO {
        throw FailingMemoryAPIError.expectedFailure
    }

    func deleteMemory(id: UUID) async throws {
        throw FailingMemoryAPIError.expectedFailure
    }
}

private enum FailingMemoryAPIError: LocalizedError {
    case expectedFailure

    var errorDescription: String? {
        "Expected memory API failure."
    }
}

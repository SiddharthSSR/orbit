import Foundation

actor MockMemoryAPIClient: MemoryAPIClientProtocol {
    private var memoryItems: [MemoryDTO]
    private var createRequests: [MemoryCreateRequest] = []

    init(memoryItems: [MemoryDTO] = MockMemoryAPIClient.previewMemoryItems) {
        self.memoryItems = memoryItems
    }

    func recordedCreateRequests() -> [MemoryCreateRequest] {
        createRequests
    }

    func listMemory(includeArchived: Bool = false, kind: String? = nil, tag: String? = nil) async throws -> [MemoryDTO] {
        memoryItems.filter { item in
            if !includeArchived, item.isArchived {
                return false
            }
            if let kind, !kind.isEmpty, item.kind != kind {
                return false
            }
            if let tag, !tag.isEmpty, !item.tags.contains(tag) {
                return false
            }
            return true
        }
    }

    func createMemory(_ payload: MemoryCreateRequest) async throws -> MemoryDTO {
        createRequests.append(payload)
        let now = Date()
        let memory = MemoryDTO(
            id: UUID(),
            title: payload.title,
            body: payload.body,
            kind: payload.kind,
            sourceUrl: payload.sourceUrl,
            tags: payload.tags,
            isArchived: payload.isArchived,
            createdAt: now,
            updatedAt: now
        )
        memoryItems.insert(memory, at: 0)
        return memory
    }

    func updateMemory(id: UUID, payload: MemoryUpdateRequest) async throws -> MemoryDTO {
        guard let index = memoryItems.firstIndex(where: { $0.id == id }) else {
            throw OrbitAPIError.requestFailed(statusCode: 404, message: "Memory item not found")
        }

        var memory = memoryItems[index]
        if let title = payload.title {
            memory.title = title
        }
        if let body = payload.body {
            memory.body = body
        }
        if let kind = payload.kind {
            memory.kind = kind
        }
        if let sourceUrl = payload.sourceUrl {
            memory.sourceUrl = sourceUrl
        }
        if let tags = payload.tags {
            memory.tags = tags
        }
        if let isArchived = payload.isArchived {
            memory.isArchived = isArchived
        }
        memory.updatedAt = Date()

        memoryItems[index] = memory
        return memory
    }

    func deleteMemory(id: UUID) async throws {
        memoryItems.removeAll { $0.id == id }
    }

    private static let previewMemoryItems: [MemoryDTO] = [
        MemoryDTO(
            id: UUID(),
            title: "AI article link",
            body: "Read later: practical approaches to personal AI memory.",
            kind: "link",
            sourceUrl: "https://example.com/ai-memory",
            tags: ["ai", "read-later"],
            isArchived: false,
            createdAt: Date(),
            updatedAt: Date()
        ),
        MemoryDTO(
            id: UUID(),
            title: "iPhone app idea",
            body: "Quick capture should accept text, links, and tasks from one field.",
            kind: "idea",
            sourceUrl: nil,
            tags: ["orbit", "ios"],
            isArchived: false,
            createdAt: Date(),
            updatedAt: Date()
        ),
        MemoryDTO(
            id: UUID(),
            title: "WorldLens project update",
            body: "Need to define the next milestone and unblock design review.",
            kind: "project_update",
            sourceUrl: nil,
            tags: ["worldlens", "projects"],
            isArchived: false,
            createdAt: Date(),
            updatedAt: Date()
        )
    ]
}

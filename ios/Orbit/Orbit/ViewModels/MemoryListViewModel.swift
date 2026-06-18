import Foundation

@MainActor
final class MemoryListViewModel: ObservableObject {
    @Published private(set) var memoryItems: [MemoryDTO] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?
    @Published var activeKindFilter: String?
    @Published var activeTagFilter: String?

    private let apiClient: any MemoryAPIClientProtocol
    private let notificationCenter: NotificationCenter

    init(
        apiClient: any MemoryAPIClientProtocol = OrbitAPIClient(),
        notificationCenter: NotificationCenter = .default
    ) {
        self.apiClient = apiClient
        self.notificationCenter = notificationCenter
    }

    func loadMemory(showsLoading: Bool = true) async {
        if showsLoading {
            isLoading = true
        }
        errorMessage = nil
        defer { isLoading = false }

        do {
            memoryItems = try await apiClient.listMemory(
                includeArchived: false,
                kind: activeKindFilter,
                tag: activeTagFilter
            )
        } catch {
            errorMessage = readableMessage(for: error)
        }
    }

    func setKindFilter(_ kind: String?) async {
        activeKindFilter = kind
        await loadMemory()
    }

    func setTagFilter(_ tag: String?) async {
        let trimmedTag = tag?.trimmingCharacters(in: .whitespacesAndNewlines)
        activeTagFilter = trimmedTag?.isEmpty == true ? nil : trimmedTag
        await loadMemory()
    }

    func createMemory(
        title: String,
        body: String,
        kind: String = "note",
        sourceURL: String? = nil,
        tags: [String] = []
    ) async {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty, !trimmedBody.isEmpty else { return }

        let trimmedSourceURL = sourceURL?.trimmingCharacters(in: .whitespacesAndNewlines)
        let payload = MemoryCreateRequest(
            title: trimmedTitle,
            body: trimmedBody,
            kind: kind,
            sourceUrl: trimmedSourceURL?.isEmpty == true ? nil : trimmedSourceURL,
            tags: normalizeTags(tags)
        )

        errorMessage = nil
        do {
            let memory = try await apiClient.createMemory(payload)
            if shouldShow(memory) {
                memoryItems.insert(memory, at: 0)
            }
            OrbitRefreshCenter.postMemoryDidChange(on: notificationCenter)
        } catch {
            errorMessage = readableMessage(for: error)
        }
    }

    func archiveMemory(memory: MemoryDTO) async {
        errorMessage = nil
        do {
            let archived = try await apiClient.updateMemory(
                id: memory.id,
                payload: MemoryUpdateRequest(isArchived: true)
            )
            if archived.isArchived {
                memoryItems.removeAll { $0.id == archived.id }
            } else {
                replace(archived)
            }
            OrbitRefreshCenter.postMemoryDidChange(on: notificationCenter)
        } catch {
            errorMessage = readableMessage(for: error)
        }
    }

    func deleteMemory(memory: MemoryDTO) async {
        errorMessage = nil
        do {
            try await apiClient.deleteMemory(id: memory.id)
            memoryItems.removeAll { $0.id == memory.id }
            OrbitRefreshCenter.postMemoryDidChange(on: notificationCenter)
        } catch {
            errorMessage = readableMessage(for: error)
        }
    }

    private func replace(_ memory: MemoryDTO) {
        guard let index = memoryItems.firstIndex(where: { $0.id == memory.id }) else {
            if shouldShow(memory) {
                memoryItems.insert(memory, at: 0)
            }
            return
        }
        if shouldShow(memory) {
            memoryItems[index] = memory
        } else {
            memoryItems.remove(at: index)
        }
    }

    private func shouldShow(_ memory: MemoryDTO) -> Bool {
        if memory.isArchived {
            return false
        }
        if let activeKindFilter, memory.kind != activeKindFilter {
            return false
        }
        if let activeTagFilter, !memory.tags.contains(activeTagFilter) {
            return false
        }
        return true
    }

    private func normalizeTags(_ tags: [String]) -> [String] {
        var normalized: [String] = []
        var seen = Set<String>()
        for tag in tags {
            let trimmedTag = tag.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedTag.isEmpty, !seen.contains(trimmedTag) else { continue }
            normalized.append(trimmedTag)
            seen.insert(trimmedTag)
        }
        return normalized
    }

    private func readableMessage(for error: Error) -> String {
        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription {
            return description
        }
        return error.localizedDescription
    }
}

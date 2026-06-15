import Foundation

@MainActor
final class ProjectListViewModel: ObservableObject {
    @Published private(set) var projects: [ProjectDTO] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?
    @Published var activeStatusFilter: String?
    @Published var activeAreaFilter: String?
    @Published var activeTagFilter: String?

    private let apiClient: any ProjectAPIClientProtocol

    init(apiClient: any ProjectAPIClientProtocol = OrbitAPIClient()) {
        self.apiClient = apiClient
    }

    func loadProjects() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            projects = try await apiClient.listProjects(
                includeArchived: false,
                status: activeStatusFilter,
                area: activeAreaFilter,
                tag: activeTagFilter
            )
        } catch {
            errorMessage = readableMessage(for: error)
        }
    }

    func createProject(
        name: String,
        description: String? = nil,
        status: String = "active",
        area: String? = nil,
        tags: [String] = []
    ) async {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        let trimmedDescription = description?.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedArea = area?.trimmingCharacters(in: .whitespacesAndNewlines)
        let payload = ProjectCreateRequest(
            name: trimmedName,
            description: trimmedDescription?.isEmpty == true ? nil : trimmedDescription,
            status: status,
            area: trimmedArea?.isEmpty == true ? nil : trimmedArea,
            tags: normalizeTags(tags)
        )

        errorMessage = nil
        do {
            let project = try await apiClient.createProject(payload)
            if shouldShow(project) {
                projects.insert(project, at: 0)
            }
        } catch {
            errorMessage = readableMessage(for: error)
        }
    }

    func updateProjectStatus(project: ProjectDTO, status: String) async {
        errorMessage = nil
        do {
            let updatedProject = try await apiClient.updateProject(
                id: project.id,
                payload: ProjectUpdateRequest(status: status)
            )
            replace(updatedProject)
        } catch {
            errorMessage = readableMessage(for: error)
        }
    }

    func archiveProject(project: ProjectDTO) async {
        await updateProjectStatus(project: project, status: "archived")
    }

    func deleteProject(project: ProjectDTO) async {
        errorMessage = nil
        do {
            try await apiClient.deleteProject(id: project.id)
            projects.removeAll { $0.id == project.id }
        } catch {
            errorMessage = readableMessage(for: error)
        }
    }

    func setStatusFilter(_ status: String?) async {
        let trimmedStatus = status?.trimmingCharacters(in: .whitespacesAndNewlines)
        activeStatusFilter = trimmedStatus?.isEmpty == true ? nil : trimmedStatus
        await loadProjects()
    }

    func setAreaFilter(_ area: String?) async {
        let trimmedArea = area?.trimmingCharacters(in: .whitespacesAndNewlines)
        activeAreaFilter = trimmedArea?.isEmpty == true ? nil : trimmedArea
        await loadProjects()
    }

    func setTagFilter(_ tag: String?) async {
        let trimmedTag = tag?.trimmingCharacters(in: .whitespacesAndNewlines)
        activeTagFilter = trimmedTag?.isEmpty == true ? nil : trimmedTag
        await loadProjects()
    }

    private func replace(_ project: ProjectDTO) {
        guard let index = projects.firstIndex(where: { $0.id == project.id }) else {
            if shouldShow(project) {
                projects.insert(project, at: 0)
            }
            return
        }
        if shouldShow(project) {
            projects[index] = project
        } else {
            projects.remove(at: index)
        }
    }

    private func shouldShow(_ project: ProjectDTO) -> Bool {
        if project.status == "archived" {
            return false
        }
        if let activeStatusFilter, project.status != activeStatusFilter {
            return false
        }
        if let activeAreaFilter, project.area != activeAreaFilter {
            return false
        }
        if let activeTagFilter, !project.tags.contains(activeTagFilter) {
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

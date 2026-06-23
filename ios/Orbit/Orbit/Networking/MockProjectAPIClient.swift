import Foundation

enum MockOrbitFixtureIDs {
    static let orbitProjectID = UUID(uuidString: "55555555-5555-5555-5555-555555555555")!
}

actor MockProjectAPIClient: ProjectAPIClientProtocol {
    private var projects: [ProjectDTO]

    init(projects: [ProjectDTO] = MockProjectAPIClient.previewProjects) {
        self.projects = projects
    }

    func listProjects(
        includeArchived: Bool = false,
        status: String? = nil,
        area: String? = nil,
        tag: String? = nil
    ) async throws -> [ProjectDTO] {
        projects.filter { project in
            if !includeArchived, project.status == "archived" {
                return false
            }
            if let status, !status.isEmpty, project.status != status {
                return false
            }
            if let area, !area.isEmpty, project.area != area {
                return false
            }
            if let tag, !tag.isEmpty, !project.tags.contains(tag) {
                return false
            }
            return true
        }
    }

    func createProject(_ payload: ProjectCreateRequest) async throws -> ProjectDTO {
        let now = Date()
        let project = ProjectDTO(
            id: UUID(),
            name: payload.name,
            description: payload.description,
            status: payload.status,
            area: payload.area,
            tags: payload.tags,
            createdAt: now,
            updatedAt: now
        )
        projects.insert(project, at: 0)
        return project
    }

    func updateProject(id: UUID, payload: ProjectUpdateRequest) async throws -> ProjectDTO {
        guard let index = projects.firstIndex(where: { $0.id == id }) else {
            throw OrbitAPIError.requestFailed(statusCode: 404, message: "Project not found")
        }

        var project = projects[index]
        if let name = payload.name {
            project.name = name
        }
        if let description = payload.description {
            project.description = description
        }
        if let status = payload.status {
            project.status = status
        }
        if let area = payload.area {
            project.area = area
        }
        if let tags = payload.tags {
            project.tags = tags
        }
        project.updatedAt = Date()

        projects[index] = project
        return project
    }

    func deleteProject(id: UUID) async throws {
        projects.removeAll { $0.id == id }
    }

    private static let previewProjects: [ProjectDTO] = [
        ProjectDTO(
            id: MockOrbitFixtureIDs.orbitProjectID,
            name: "Orbit",
            description: "Personal iPhone second brain MVP.",
            status: "active",
            area: "orbit",
            tags: ["ios", "backend"],
            createdAt: Date(),
            updatedAt: Date()
        ),
        ProjectDTO(
            id: UUID(),
            name: "WorldLens",
            description: "Define the next milestone and product surface.",
            status: "paused",
            area: "worldlens",
            tags: ["product"],
            createdAt: Date(),
            updatedAt: Date()
        ),
        ProjectDTO(
            id: UUID(),
            name: "AI Systems Learning",
            description: "Track reading, experiments, and implementation notes.",
            status: "active",
            area: "learning",
            tags: ["ai", "learning"],
            createdAt: Date(),
            updatedAt: Date()
        )
    ]
}

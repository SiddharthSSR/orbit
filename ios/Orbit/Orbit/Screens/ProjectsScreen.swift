import SwiftUI

struct ProjectsScreen: View {
    @StateObject private var projectViewModel: ProjectListViewModel
    @State private var selectedProject: ProjectDTO?
    @State private var newProjectName = ""
    @State private var newProjectDescription = ""
    @State private var newProjectStatus = "active"
    @State private var newProjectArea = ""
    @State private var newProjectTags = ""
    @State private var statusFilter = "all"
    @State private var areaFilter = ""
    @State private var tagFilter = ""

    private let statusOptions = ["active", "paused", "completed"]
    private let filterOptions = ["all", "active", "paused", "completed"]
    private let memoryAPIClient: any MemoryAPIClientProtocol
    private let todoAPIClient: any TodoAPIClientProtocol

    init(
        apiClient: any ProjectAPIClientProtocol = OrbitAPIClient(),
        memoryAPIClient: any MemoryAPIClientProtocol = OrbitAPIClient(),
        todoAPIClient: any TodoAPIClientProtocol = OrbitAPIClient()
    ) {
        _projectViewModel = StateObject(wrappedValue: ProjectListViewModel(apiClient: apiClient))
        self.memoryAPIClient = memoryAPIClient
        self.todoAPIClient = todoAPIClient
    }

    var body: some View {
        List {
            Section("Add project") {
                TextField("Name", text: $newProjectName)
                    .textInputAutocapitalization(.words)

                TextField("Description (optional)", text: $newProjectDescription, axis: .vertical)
                    .lineLimit(1...3)

                Picker("Status", selection: $newProjectStatus) {
                    ForEach(statusOptions, id: \.self) { status in
                        Text(statusLabel(status)).tag(status)
                    }
                }
                .pickerStyle(.segmented)

                TextField("Area (optional)", text: $newProjectArea)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                TextField("Tags, comma separated", text: $newProjectTags)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                Button {
                    Task { await createProject() }
                } label: {
                    Label("Add project", systemImage: "folder.badge.plus")
                }
                .disabled(newProjectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            Section("Filters") {
                Picker("Status", selection: $statusFilter) {
                    ForEach(filterOptions, id: \.self) { status in
                        Text(status == "all" ? "All" : statusLabel(status)).tag(status)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: statusFilter) { _, newValue in
                    Task {
                        await projectViewModel.setStatusFilter(newValue == "all" ? nil : newValue)
                    }
                }

                TextField("Area filter", text: $areaFilter)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit {
                        Task { await projectViewModel.setAreaFilter(areaFilter) }
                    }

                TextField("Tag filter", text: $tagFilter)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit {
                        Task { await projectViewModel.setTagFilter(tagFilter) }
                    }

                Button {
                    Task {
                        statusFilter = "all"
                        areaFilter = ""
                        tagFilter = ""
                        await projectViewModel.setStatusFilter(nil)
                        await projectViewModel.setAreaFilter(nil)
                        await projectViewModel.setTagFilter(nil)
                    }
                } label: {
                    Label("Clear filters", systemImage: "line.3.horizontal.decrease.circle")
                }
            }

            if let errorMessage = projectViewModel.errorMessage {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                        Button {
                            Task { await projectViewModel.loadProjects() }
                        } label: {
                            Label("Retry", systemImage: "arrow.clockwise")
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            Section {
                if projectViewModel.isLoading {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                } else if projectViewModel.projects.isEmpty {
                    EmptyStateView(
                        title: "No projects yet",
                        message: "Track active areas of work and connect todos to them.",
                        systemImage: "folder"
                    )
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(projectViewModel.projects) { project in
                        ProjectRow(
                            project: project,
                            onOpen: {
                                selectedProject = project
                            },
                            onMarkActive: {
                                Task { await projectViewModel.updateProjectStatus(project: project, status: "active") }
                            },
                            onMarkPaused: {
                                Task { await projectViewModel.updateProjectStatus(project: project, status: "paused") }
                            },
                            onMarkCompleted: {
                                Task { await projectViewModel.updateProjectStatus(project: project, status: "completed") }
                            },
                            onArchive: {
                                Task { await projectViewModel.archiveProject(project: project) }
                            },
                            onDelete: {
                                Task { await projectViewModel.deleteProject(project: project) }
                            }
                        )
                    }
                }
            } header: {
                OrbitSectionHeader("Projects") {
                    if !projectViewModel.projects.isEmpty {
                        OrbitBadge(text: "\(projectViewModel.projects.count) shown")
                    }
                }
                .textCase(nil)
            }
        }
        .scrollContentBackground(.hidden)
        .orbitBackground()
        .task {
            await projectViewModel.loadProjects()
        }
        .navigationDestination(item: $selectedProject) { project in
            ProjectDetailScreen(
                project: project,
                memoryAPIClient: memoryAPIClient,
                todoAPIClient: todoAPIClient
            )
        }
    }

    private func createProject() async {
        await projectViewModel.createProject(
            name: newProjectName,
            description: newProjectDescription,
            status: newProjectStatus,
            area: newProjectArea,
            tags: parseTags(newProjectTags)
        )

        if projectViewModel.errorMessage == nil {
            newProjectName = ""
            newProjectDescription = ""
            newProjectStatus = "active"
            newProjectArea = ""
            newProjectTags = ""
        }
    }

    private func parseTags(_ value: String) -> [String] {
        value.split(separator: ",").map { String($0) }
    }

    private func statusLabel(_ status: String) -> String {
        status.capitalized
    }
}

private struct ProjectRow: View {
    let project: ProjectDTO
    let onOpen: () -> Void
    let onMarkActive: () -> Void
    let onMarkPaused: () -> Void
    let onMarkCompleted: () -> Void
    let onArchive: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: OrbitSpacing.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text(project.name)
                    .font(OrbitTypography.cardTitle)
                Spacer(minLength: OrbitSpacing.xs)
                OrbitBadge(text: project.status.capitalized, tint: statusColor(project.status))
            }

            if let description = project.description, !description.isEmpty {
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }

            if let area = project.area, !area.isEmpty {
                Label(area, systemImage: "square.grid.2x2")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !project.tags.isEmpty {
                Label(project.tags.joined(separator: " · "), systemImage: "tag")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
            }

            HStack(spacing: 14) {
                Button(action: onOpen) {
                    Label("Details", systemImage: "chevron.right.circle")
                }
                .accessibilityLabel("Open \(project.name) project")

                Button(action: onMarkActive) {
                    Label("Active", systemImage: "play.circle")
                }
                .disabled(project.status == "active")

                Button(action: onMarkPaused) {
                    Label("Pause", systemImage: "pause.circle")
                }
                .disabled(project.status == "paused")

                Button(action: onMarkCompleted) {
                    Label("Done", systemImage: "checkmark.circle")
                }
                .disabled(project.status == "completed")

                Spacer()

                Button(action: onArchive) {
                    Image(systemName: "archivebox")
                }
                .accessibilityLabel("Archive project")

                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
                .accessibilityLabel("Delete project")
            }
            .buttonStyle(.borderless)
            .font(.subheadline)
        }
        .orbitFloatingCard()
        .orbitListCardRow()
    }

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "active":
            .green
        case "paused":
            .orange
        case "completed":
            .blue
        default:
            .secondary
        }
    }
}

private struct ProjectDetailScreen: View {
    let project: ProjectDTO
    let memoryAPIClient: any MemoryAPIClientProtocol
    let todoAPIClient: any TodoAPIClientProtocol

    @State private var linkedTodos: [TodoDTO] = []
    @State private var isLoadingTodos = false
    @State private var todoErrorMessage: String?
    @State private var linkedMemories: [MemoryDTO] = []
    @State private var isLoadingMemories = false
    @State private var memoryErrorMessage: String?

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: OrbitSpacing.md) {
                    OrbitScreenMasthead(
                        project.name,
                        subtitle: project.description
                    )

                    VStack(alignment: .leading, spacing: OrbitSpacing.xs) {
                        HStack {
                            OrbitBadge(text: project.status.capitalized, tint: statusColor(project.status))
                            if let area = project.area, !area.isEmpty {
                                OrbitBadge(text: area, tint: .accentColor)
                            }
                        }

                        if !project.tags.isEmpty {
                            Label(project.tags.joined(separator: " · "), systemImage: "tag")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                }
                .orbitFloatingCard()
                .orbitListCardRow()
            }

            Section {
                if isLoadingTodos {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                } else if let todoErrorMessage {
                    VStack(alignment: .leading, spacing: OrbitSpacing.xs) {
                        Label(todoErrorMessage, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                        Button {
                            Task { await loadLinkedTodos() }
                        } label: {
                            Label("Retry todos", systemImage: "arrow.clockwise")
                        }
                    }
                    .orbitFloatingCard()
                    .orbitListCardRow()
                } else if linkedTodos.isEmpty {
                    EmptyStateView(
                        title: "No linked todos yet",
                        message: "Linked project tasks will appear here.",
                        systemImage: "checklist"
                    )
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(linkedTodos) { todo in
                        ProjectLinkedTodoRow(todo: todo)
                    }
                }
            } header: {
                OrbitSectionHeader("Linked todos", systemImage: "checklist") {
                    if !linkedTodos.isEmpty {
                        OrbitBadge(text: "\(linkedTodos.count)")
                    }
                }
                .textCase(nil)
            }

            Section {
                if isLoadingMemories {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                } else if let memoryErrorMessage {
                    VStack(alignment: .leading, spacing: OrbitSpacing.xs) {
                        Label(memoryErrorMessage, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                        Button {
                            Task { await loadLinkedMemories() }
                        } label: {
                            Label("Retry memories", systemImage: "arrow.clockwise")
                        }
                    }
                    .orbitFloatingCard()
                    .orbitListCardRow()
                } else if linkedMemories.isEmpty {
                    EmptyStateView(
                        title: "No linked memories yet",
                        message: "Link memories from Inbox and they will appear here.",
                        systemImage: "tray"
                    )
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(linkedMemories) { memory in
                        ProjectLinkedMemoryRow(memory: memory)
                    }
                }
            } header: {
                OrbitSectionHeader("Linked memories", systemImage: "tray") {
                    if !linkedMemories.isEmpty {
                        OrbitBadge(text: "\(linkedMemories.count)")
                    }
                }
                .textCase(nil)
            }
        }
        .navigationTitle(project.name)
        .navigationBarTitleDisplayMode(.inline)
        .scrollContentBackground(.hidden)
        .orbitBackground()
        .task(id: project.id) {
            await loadProjectLinks()
        }
        .onReceive(OrbitRefreshCenter.publisher(for: OrbitRefreshCenter.todoDidChange)) { _ in
            Task { await loadLinkedTodos() }
        }
        .onReceive(OrbitRefreshCenter.publisher(for: OrbitRefreshCenter.memoryDidChange)) { _ in
            Task { await loadLinkedMemories() }
        }
    }

    private func loadProjectLinks() async {
        await loadLinkedTodos()
        await loadLinkedMemories()
    }

    private func loadLinkedTodos() async {
        isLoadingTodos = true
        todoErrorMessage = nil
        defer { isLoadingTodos = false }

        do {
            linkedTodos = try await todoAPIClient.listTodos(projectId: project.id)
        } catch {
            todoErrorMessage = readableMessage(for: error)
            linkedTodos = []
        }
    }

    private func loadLinkedMemories() async {
        isLoadingMemories = true
        memoryErrorMessage = nil
        defer { isLoadingMemories = false }

        do {
            linkedMemories = try await memoryAPIClient.listMemory(
                includeArchived: false,
                kind: nil,
                tag: nil,
                projectId: project.id
            )
        } catch {
            memoryErrorMessage = readableMessage(for: error)
            linkedMemories = []
        }
    }

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "active":
            .green
        case "paused":
            .orange
        case "completed":
            .blue
        default:
            .secondary
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

private struct ProjectLinkedTodoRow: View {
    let todo: TodoDTO

    var body: some View {
        VStack(alignment: .leading, spacing: OrbitSpacing.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text(todo.title)
                    .font(OrbitTypography.cardTitle)
                Spacer(minLength: OrbitSpacing.xs)
                OrbitBadge(
                    text: todo.isComplete ? "Completed" : "Open",
                    tint: todo.isComplete ? .secondary : .green
                )
            }

            if let notes = todo.notes, !notes.isEmpty {
                Text(notes)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if let urgency = TodoUrgency.resolve(dueDate: todo.dueDate) {
                Label(urgency.label, systemImage: "calendar")
                    .font(.caption)
                    .foregroundStyle(urgencyTint(urgency))
                    .padding(.top, OrbitSpacing.xxs)
            }
        }
        .orbitFloatingCard()
        .orbitListCardRow()
    }

    private func urgencyTint(_ urgency: TodoUrgency) -> Color {
        switch urgency {
        case .overdue:
            .red
        case .today:
            .orange
        case .tomorrow, .upcoming:
            .secondary
        }
    }
}

private struct ProjectLinkedMemoryRow: View {
    let memory: MemoryDTO

    var body: some View {
        VStack(alignment: .leading, spacing: OrbitSpacing.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text(memory.title)
                    .font(OrbitTypography.cardTitle)
                Spacer(minLength: OrbitSpacing.xs)
                OrbitBadge(text: kindLabel(memory.kind))
            }

            Text(memory.body)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(3)

            VStack(alignment: .leading, spacing: OrbitSpacing.xxs) {
                if let sourceHost {
                    Label(sourceHost, systemImage: "link")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if !memory.tags.isEmpty {
                    Label(memory.tags.joined(separator: " · "), systemImage: "tag")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                }

                Label(
                    "Captured \(memory.createdAt.formatted(date: .abbreviated, time: .omitted))",
                    systemImage: "clock"
                )
                .font(.caption)
                .foregroundStyle(.tertiary)
            }
            .padding(.top, OrbitSpacing.xxs)
        }
        .orbitFloatingCard()
        .orbitListCardRow()
    }

    private var sourceHost: String? {
        guard let sourceUrl = memory.sourceUrl, !sourceUrl.isEmpty else { return nil }
        return URL(string: sourceUrl)?.host ?? sourceUrl
    }

    private func kindLabel(_ kind: String) -> String {
        switch kind {
        case "project_update":
            "Project"
        default:
            kind.capitalized
        }
    }
}

struct ProjectsScreen_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            ProjectsScreen(
                apiClient: MockProjectAPIClient(),
                memoryAPIClient: MockMemoryAPIClient(),
                todoAPIClient: MockTodoAPIClient()
            )
                .navigationTitle("Projects")
        }
    }
}

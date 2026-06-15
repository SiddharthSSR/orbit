import SwiftUI

struct ProjectsScreen: View {
    @StateObject private var projectViewModel: ProjectListViewModel
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

    init(apiClient: any ProjectAPIClientProtocol = OrbitAPIClient()) {
        _projectViewModel = StateObject(wrappedValue: ProjectListViewModel(apiClient: apiClient))
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

            Section("Projects") {
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
            }
        }
        .task {
            await projectViewModel.loadProjects()
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
    let onMarkActive: () -> Void
    let onMarkPaused: () -> Void
    let onMarkCompleted: () -> Void
    let onArchive: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(project.name)
                    .font(.headline)
                Spacer(minLength: 8)
                Text(project.status.capitalized)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(statusColor(project.status))
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
                Text(project.tags.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
            }

            HStack(spacing: 14) {
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
        .padding(.vertical, 4)
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

struct ProjectsScreen_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            ProjectsScreen(apiClient: MockProjectAPIClient())
                .navigationTitle("Projects")
        }
    }
}

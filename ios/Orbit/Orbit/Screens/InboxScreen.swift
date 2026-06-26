import SwiftUI

struct InboxScreen: View {
    @EnvironmentObject private var navigation: AppNavigationModel
    @StateObject private var memoryViewModel: MemoryListViewModel
    @State private var highlightedMemoryID: UUID?
    @State private var selectedMemory: MemoryDTO?
    @State private var newTitle = ""
    @State private var newBody = ""
    @State private var newKind = "note"
    @State private var newSourceURL = ""
    @State private var newTags = ""

    private let kindOptions = ["note", "idea", "link", "project_update"]

    init(
        apiClient: any MemoryAPIClientProtocol = OrbitAPIClient(),
        projectAPIClient: any ProjectAPIClientProtocol = OrbitAPIClient()
    ) {
        _memoryViewModel = StateObject(
            wrappedValue: MemoryListViewModel(
                apiClient: apiClient,
                projectAPIClient: projectAPIClient
            )
        )
    }

    var body: some View {
        List {
            Section("Capture") {
                TextField("Title", text: $newTitle)
                    .textInputAutocapitalization(.sentences)

                TextField("Body", text: $newBody, axis: .vertical)
                    .lineLimit(3...6)

                Picker("Kind", selection: $newKind) {
                    ForEach(kindOptions, id: \.self) { kind in
                        Text(kindLabel(kind)).tag(kind)
                    }
                }
                .pickerStyle(.segmented)

                TextField("Source URL (optional)", text: $newSourceURL)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                TextField("Tags, comma separated", text: $newTags)
                    .textInputAutocapitalization(.never)

                Button {
                    Task { await createMemory() }
                } label: {
                    Label("Save to inbox", systemImage: "tray.and.arrow.down.fill")
                }
                .disabled(
                    newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                    newBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
            }

            if let errorMessage = memoryViewModel.errorMessage {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                        Button {
                            Task { await memoryViewModel.loadMemory() }
                        } label: {
                            Label("Retry", systemImage: "arrow.clockwise")
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            if let projectErrorMessage = memoryViewModel.projectLoadErrorMessage {
                Section {
                    VStack(alignment: .leading, spacing: OrbitSpacing.xs) {
                        Label(projectErrorMessage, systemImage: "folder.badge.questionmark")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Button("Retry projects") {
                            Task { await memoryViewModel.loadProjects() }
                        }
                    }
                    .padding(.vertical, OrbitSpacing.xxs)
                }
            }

            Section {
                if memoryViewModel.isLoading {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                } else if memoryViewModel.memoryItems.isEmpty {
                    EmptyStateView(
                        title: "Inbox is empty",
                        message: "Saved links, articles, and quick notes will appear here.",
                        systemImage: "tray"
                    )
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                } else {
                    Picker("Filter captures", selection: $memoryViewModel.activeInboxFilter) {
                        ForEach(InboxMemoryFilter.allCases) { filter in
                            Text(filter.title).tag(filter)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .accessibilityIdentifier("Inbox filter")

                    if memoryViewModel.filteredMemoryItems.isEmpty {
                        EmptyStateView(
                            title: "No matching captures",
                            message: "No memories match this filter. Switch back to All to see everything.",
                            systemImage: "line.3.horizontal.decrease.circle"
                        )
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                    } else {
                        ForEach(memoryViewModel.filteredMemoryItems) { memory in
                            MemoryRow(
                                memory: memory,
                                projects: memoryViewModel.projects,
                                projectName: memoryViewModel.projectName(for: memory.projectId),
                                projectLinkErrorMessage: memoryViewModel.projectLinkErrorMessages[memory.id],
                                isUpdatingProject: memoryViewModel.updatingProjectMemoryIDs.contains(memory.id),
                                isHighlighted: memory.id == highlightedMemoryID,
                                onOpen: { selectedMemory = memory },
                                onProjectSelected: { projectID in
                                    Task {
                                        await memoryViewModel.updateProjectLink(
                                            memory: memory,
                                            projectID: projectID
                                        )
                                    }
                                },
                                onArchive: {
                                    Task { await memoryViewModel.archiveMemory(memory: memory) }
                                },
                                onDelete: {
                                    Task { await memoryViewModel.deleteMemory(memory: memory) }
                                }
                            )
                        }
                    }
                }
            } header: {
                OrbitSectionHeader("Captured") {
                    if !memoryViewModel.memoryItems.isEmpty {
                        OrbitBadge(text: "\(memoryViewModel.memoryItems.count) saved")
                    }
                }
                .textCase(nil)
            }
        }
        .scrollContentBackground(.hidden)
        .orbitBackground()
        .navigationDestination(item: $selectedMemory) { memory in
            MemoryDetailView(
                memory: memory,
                projectName: memoryViewModel.projectName(for: memory.projectId)
            )
        }
        .task {
            await memoryViewModel.loadMemory()
            consumePendingHighlightIfLoaded()
            await memoryViewModel.loadProjects()
        }
        .task(id: highlightedMemoryID) {
            guard let highlightedMemoryID else { return }
            do {
                try await Task.sleep(for: .seconds(2))
            } catch {
                return
            }
            guard self.highlightedMemoryID == highlightedMemoryID else { return }
            withAnimation(.easeOut(duration: 0.25)) {
                self.highlightedMemoryID = nil
            }
        }
        .onChange(of: memoryViewModel.memoryItems) { _, _ in
            consumePendingHighlightIfLoaded()
        }
        .onChange(of: navigation.pendingHighlight) { _, _ in
            consumePendingHighlightIfLoaded()
        }
        .onReceive(
            OrbitRefreshCenter.publisher(for: .orbitMemoryDidChange)
        ) { _ in
            Task {
                await memoryViewModel.loadMemory(showsLoading: false)
                consumePendingHighlightIfLoaded()
            }
        }
    }

    private func consumePendingHighlightIfLoaded() {
        guard case let .memory(id)? = navigation.pendingHighlight,
              memoryViewModel.memoryItems.contains(where: { $0.id == id }),
              navigation.consumeHighlight(.memory(id)) else {
            return
        }
        withAnimation(.easeIn(duration: 0.2)) {
            highlightedMemoryID = id
        }
    }

    private func createMemory() async {
        await memoryViewModel.createMemory(
            title: newTitle,
            body: newBody,
            kind: newKind,
            sourceURL: newSourceURL,
            tags: parseTags(newTags)
        )

        if memoryViewModel.errorMessage == nil {
            newTitle = ""
            newBody = ""
            newKind = "note"
            newSourceURL = ""
            newTags = ""
        }
    }

    private func parseTags(_ value: String) -> [String] {
        value.split(separator: ",").map { String($0) }
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

private struct MemoryRow: View {
    let memory: MemoryDTO
    let projects: [ProjectDTO]
    let projectName: String?
    let projectLinkErrorMessage: String?
    let isUpdatingProject: Bool
    let isHighlighted: Bool
    let onOpen: () -> Void
    let onProjectSelected: (UUID?) -> Void
    let onArchive: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: OrbitSpacing.xs) {
            // Only the content area navigates to the read-only detail; the action
            // row below stays outside this button so the project menu, archive,
            // and delete controls keep their own taps.
            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: OrbitSpacing.xs) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(memory.title)
                            .font(OrbitTypography.cardTitle)
                        Spacer(minLength: OrbitSpacing.xs)
                        if quality.needsReview {
                            OrbitBadge(text: "Needs review", tint: .orange)
                                .accessibilityLabel("Needs review: no project, tags, or source")
                        }
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

                        if let projectName {
                            LinkedProjectLabel(projectName: projectName)
                                .accessibilityIdentifier("Linked project for \(memory.title)")
                        } else if memory.projectId != nil {
                            Label("Linked project", systemImage: "folder")
                                .font(.caption)
                                .foregroundStyle(.secondary)
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
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("Open memory \(memory.title)")
            .accessibilityHint("Opens memory details")

            HStack {
                Menu {
                    projectButton(name: "Unlinked", projectID: nil)
                    ForEach(projects) { project in
                        projectButton(name: project.name, projectID: project.id)
                    }
                } label: {
                    Label("Project", systemImage: "folder")
                }
                .disabled(isUpdatingProject)
                .accessibilityLabel("Project for \(memory.title)")

                Button(action: onArchive) {
                    Label("Archive", systemImage: "archivebox")
                }
                .buttonStyle(.borderless)

                Spacer()

                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Delete memory item")
            }
            .font(.subheadline)

            if let projectLinkErrorMessage {
                Label(projectLinkErrorMessage, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .orbitFloatingCard(isHighlighted: isHighlighted)
        .orbitListCardRow()
        .animation(.easeInOut(duration: 0.2), value: isHighlighted)
    }

    @ViewBuilder
    private func projectButton(name: String, projectID: UUID?) -> some View {
        Button {
            onProjectSelected(projectID)
        } label: {
            if memory.projectId == projectID {
                Label(name, systemImage: "checkmark")
            } else {
                Text(name)
            }
        }
    }

    /// Read-only capture-quality signals derived from the memory's existing
    /// fields, used to show the calm "needs review" cue.
    private var quality: MemoryCaptureQuality {
        MemoryCaptureQuality(memory: memory)
    }

    /// The source URL's host for a calm archive-style label, falling back to the
    /// raw string. Display-only — the value and behavior are unchanged.
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

/// Read-only detail for a single captured memory, opened from an Inbox row. It
/// reuses the already-loaded memory (and resolved project name) — no fetch, no
/// editing. Missing source/tags/project render calm "omitted" rows rather than
/// disappearing, so the capture's completeness is legible at a glance.
private struct MemoryDetailView: View {
    let memory: MemoryDTO
    let projectName: String?

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: OrbitSpacing.md) {
                    OrbitScreenMasthead(memory.title)

                    HStack(spacing: OrbitSpacing.xs) {
                        OrbitBadge(text: kindLabel(memory.kind))
                        if quality.needsReview {
                            OrbitBadge(text: "Needs review", tint: .orange)
                                .accessibilityLabel("Needs review: no project, tags, or source")
                        }
                    }

                    if let sourceURL {
                        VStack(alignment: .leading, spacing: OrbitSpacing.xxs) {
                            Label(sourceHost ?? sourceURL, systemImage: "link")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text(sourceURL)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .textSelection(.enabled)
                                .lineLimit(3)
                        }
                    } else {
                        omittedRow("No source", systemImage: "link")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .orbitFloatingCard()
                .orbitListCardRow()
            }

            Section {
                Text(memory.body)
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .orbitFloatingCard()
                    .orbitListCardRow()
            } header: {
                OrbitSectionHeader("Note", systemImage: "doc.text")
                    .textCase(nil)
            }

            Section {
                VStack(alignment: .leading, spacing: OrbitSpacing.sm) {
                    if !memory.tags.isEmpty {
                        Label(memory.tags.joined(separator: " · "), systemImage: "tag")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    } else {
                        omittedRow("No tags", systemImage: "tag")
                    }

                    Divider()

                    if let projectName {
                        LinkedProjectLabel(projectName: projectName)
                    } else if memory.projectId != nil {
                        Label("Linked project", systemImage: "folder")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        omittedRow("Not linked to a project", systemImage: "folder")
                    }

                    Divider()

                    Label(
                        "Captured \(memory.createdAt.formatted(date: .abbreviated, time: .omitted))",
                        systemImage: "clock"
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .orbitFloatingCard()
                .orbitListCardRow()
            } header: {
                OrbitSectionHeader("Details", systemImage: "info.circle")
                    .textCase(nil)
            }
        }
        .navigationTitle(memory.title)
        .navigationBarTitleDisplayMode(.inline)
        .scrollContentBackground(.hidden)
        .orbitBackground()
    }

    private var quality: MemoryCaptureQuality {
        MemoryCaptureQuality(memory: memory)
    }

    /// Trimmed, non-empty source URL or `nil`.
    private var sourceURL: String? {
        guard let trimmed = memory.sourceUrl?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }

    /// Host of the source URL for a calm label, falling back to the raw value.
    private var sourceHost: String? {
        guard let sourceURL else { return nil }
        return URL(string: sourceURL)?.host ?? sourceURL
    }

    @ViewBuilder
    private func omittedRow(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.subheadline)
            .foregroundStyle(.tertiary)
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

struct InboxScreen_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            InboxScreen(
                apiClient: MockMemoryAPIClient(),
                projectAPIClient: MockProjectAPIClient()
            )
                .navigationTitle("Inbox")
                .environmentObject(AppNavigationModel())
        }
    }
}

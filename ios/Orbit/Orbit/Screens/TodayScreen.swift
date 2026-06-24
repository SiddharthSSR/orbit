import SwiftUI

struct TodayScreen: View {
    @EnvironmentObject private var navigation: AppNavigationModel
    @StateObject private var dashboardViewModel: TodayDashboardViewModel
    @State private var highlightedTodoID: UUID?
    @State private var selectedMood = "focused"
    @State private var selectedEnergy = 3
    @State private var moodNotes = ""
    @State private var projectPickerTodoID: UUID?
    @State private var selectedProject: ProjectDTO?

    private let moodOptions = ["focused", "calm", "happy", "stressed", "tired", "anxious", "excited", "neutral"]
    private let memoryAPIClient: any MemoryAPIClientProtocol
    private let todoAPIClient: any TodoAPIClientProtocol

    init(
        todoAPIClient: any TodoAPIClientProtocol = OrbitAPIClient(),
        billAPIClient: any BillAPIClientProtocol = OrbitAPIClient(),
        memoryAPIClient: any MemoryAPIClientProtocol = OrbitAPIClient(),
        moodAPIClient: any MoodAPIClientProtocol = OrbitAPIClient(),
        projectAPIClient: any ProjectAPIClientProtocol = OrbitAPIClient()
    ) {
        _dashboardViewModel = StateObject(
            wrappedValue: TodayDashboardViewModel(
                todoAPIClient: todoAPIClient,
                billAPIClient: billAPIClient,
                memoryAPIClient: memoryAPIClient,
                moodAPIClient: moodAPIClient,
                projectAPIClient: projectAPIClient
            )
        )
        self.memoryAPIClient = memoryAPIClient
        self.todoAPIClient = todoAPIClient
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                greetingHero

                summaryCard

                if dashboardViewModel.isLoading {
                    loadingCard
                } else if let errorMessage = dashboardViewModel.errorMessage {
                    errorCard(errorMessage)
                } else {
                    moodCheckInSection
                    projectDigestSection
                    openTodosSection
                    unpaidBillsSection
                    recentMemorySection
                }
            }
            .padding()
        }
        .navigationBarTitleDisplayMode(.inline)
        .orbitBackground()
        .navigationDestination(item: $selectedProject) { project in
            ProjectDetailScreen(
                project: project,
                memoryAPIClient: memoryAPIClient,
                todoAPIClient: todoAPIClient
            )
        }
        .task {
            await dashboardViewModel.loadDashboard()
            await dashboardViewModel.loadProjects()
            consumePendingHighlightIfLoaded()
        }
        .task(id: highlightedTodoID) {
            guard let highlightedTodoID else { return }
            do {
                try await Task.sleep(for: .seconds(2))
            } catch {
                return
            }
            guard self.highlightedTodoID == highlightedTodoID else { return }
            withAnimation(.easeOut(duration: 0.25)) {
                self.highlightedTodoID = nil
            }
        }
        .onChange(of: dashboardViewModel.todos) { _, _ in
            consumePendingHighlightIfLoaded()
        }
        .onChange(of: navigation.pendingHighlight) { _, _ in
            consumePendingHighlightIfLoaded()
        }
        .onReceive(
            OrbitRefreshCenter.publisher(for: .orbitMemoryDidChange)
        ) { _ in
            Task {
                await dashboardViewModel.loadDashboard(showsLoading: false)
                consumePendingHighlightIfLoaded()
            }
        }
        .onReceive(
            OrbitRefreshCenter.publisher(for: .orbitTodoDidChange)
        ) { _ in
            Task {
                await dashboardViewModel.loadDashboard(showsLoading: false)
                consumePendingHighlightIfLoaded()
            }
        }
        .onReceive(
            OrbitRefreshCenter.publisher(for: .orbitBillsDidChange)
        ) { _ in
            Task {
                await dashboardViewModel.loadDashboard(showsLoading: false)
                consumePendingHighlightIfLoaded()
            }
        }
    }

    private func consumePendingHighlightIfLoaded() {
        guard case let .todo(id)? = navigation.pendingHighlight,
              dashboardViewModel.openTodos.contains(where: { $0.id == id }),
              navigation.consumeHighlight(.todo(id)) else {
            return
        }
        withAnimation(.easeIn(duration: 0.2)) {
            highlightedTodoID = id
        }
    }

    // Today's home greeting reuses the shared editorial masthead at hero
    // prominence; the greeting/date content stays Today-specific.
    private var greetingHero: some View {
        OrbitScreenMasthead(
            greeting,
            subtitle: Date().formatted(.dateTime.weekday(.wide).month(.wide).day()),
            prominence: .hero
        )
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12: "Good morning"
        case 12..<17: "Good afternoon"
        case 17..<22: "Good evening"
        default: "Good night"
        }
    }

    private var summaryCard: some View {
        OrbitCard {
            Label("Daily Plan", systemImage: "calendar")
                .font(OrbitTypography.cardTitle)
            Text(
                "You have \(dashboardViewModel.openTodoCount) open todos, \(dashboardViewModel.unpaidBillCount) unpaid bills, and \(dashboardViewModel.recentMemoryCount) recent captures."
            )
            .foregroundStyle(.secondary)
        }
    }

    private var loadingCard: some View {
        OrbitCard {
            HStack(spacing: 10) {
                ProgressView()
                Text("Loading today")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func errorCard(_ message: String) -> some View {
        OrbitCard {
            Label("Could not load Today", systemImage: "exclamationmark.triangle")
                .font(OrbitTypography.cardTitle)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button {
                Task { await dashboardViewModel.loadDashboard() }
            } label: {
                Label("Retry", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
        }
    }

    private var openTodosSection: some View {
        DashboardSection(
            title: "Open Todos",
            systemImage: "checklist",
            count: dashboardViewModel.openTodoCount
        ) {
            if dashboardViewModel.openTodos.isEmpty {
                EmptyStateView(
                    title: "You're caught up",
                    message: "Todos created from Ask will appear here.",
                    systemImage: "checkmark.circle"
                )
                .frame(minHeight: 120)
            } else {
                VStack(spacing: 0) {
                    ForEach(
                        dashboardViewModel.displayedOpenTodos(highlighting: highlightedTodoID)
                    ) { todo in
                        TodayTodoRow(
                            todo: todo,
                            isHighlighted: todo.id == highlightedTodoID,
                            isCompleting: dashboardViewModel.isCompletingTodo(id: todo.id),
                            projects: dashboardViewModel.projects,
                            projectName: dashboardViewModel.projectName(for: todo.projectId),
                            isShowingProjectPicker: projectPickerTodoID == todo.id,
                            isUpdatingProject: dashboardViewModel.isUpdatingProject(id: todo.id),
                            projectLinkErrorMessage: dashboardViewModel.todoProjectLinkErrors[todo.id],
                            onToggle: {
                                Task { await dashboardViewModel.toggleTodoComplete(todo: todo) }
                            },
                            onProjectPickerRequested: {
                                projectPickerTodoID = projectPickerTodoID == todo.id ? nil : todo.id
                            },
                            onProjectSelected: { projectID in
                                projectPickerTodoID = nil
                                Task {
                                    await dashboardViewModel.updateTodoProjectLink(
                                        todo: todo,
                                        projectID: projectID
                                    )
                                }
                            }
                        )
                    }
                }

                if let message = dashboardViewModel.todoCompletionErrorMessage {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Couldn't complete todo")
                                .font(.subheadline.weight(.semibold))
                            Text(message)
                                .font(.caption)
                        }
                    } icon: {
                        Image(systemName: "exclamationmark.circle")
                    }
                    .foregroundStyle(.red)
                    .padding(.top, 4)
                }
            }
        }
    }

    private var moodCheckInSection: some View {
        DashboardSection(title: "Mood Check-in", systemImage: "heart") {
            OrbitCard {
                if let latestMood = dashboardViewModel.latestMood {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(latestMood.mood.capitalized) · Energy \(latestMood.energy)/5")
                            .font(.subheadline.weight(.semibold))
                        Text("Checked in \(latestMood.checkInDate.formatted(date: .abbreviated, time: .omitted))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let notes = latestMood.notes, !notes.isEmpty {
                            Text(notes)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Text("No mood check-in yet today.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Picker("Mood", selection: $selectedMood) {
                    ForEach(moodOptions, id: \.self) { mood in
                        Text(mood.capitalized).tag(mood)
                    }
                }

                Stepper("Energy \(selectedEnergy)/5", value: $selectedEnergy, in: 1...5)

                TextField("Notes (optional)", text: $moodNotes, axis: .vertical)
                    .lineLimit(1...3)

                Button {
                    Task { await createMoodCheckIn() }
                } label: {
                    Label("Save check-in", systemImage: "heart.fill")
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var projectDigestSection: some View {
        DashboardSection(title: "Project Digest", systemImage: "folder") {
            if dashboardViewModel.projectDigestItems.isEmpty {
                OrbitCard {
                    EmptyStateView(
                        title: "No project activity yet",
                        message: "Link todos or captures to projects to see a daily digest here.",
                        systemImage: "folder"
                    )
                    .frame(minHeight: 110)
                }
            } else {
                VStack(spacing: OrbitSpacing.xs) {
                    ForEach(dashboardViewModel.projectDigestItems) { item in
                        TodayProjectDigestRow(item: item) {
                            selectedProject = item.project
                        }
                    }
                }
            }
        }
    }

    private var unpaidBillsSection: some View {
        DashboardSection(title: "Upcoming Bills", systemImage: "creditcard") {
            if dashboardViewModel.unpaidBills.isEmpty {
                EmptyStateView(
                    title: "No unpaid bills",
                    message: "Payment reminders are clear.",
                    systemImage: "checkmark.seal"
                )
                .frame(minHeight: 120)
            } else {
                VStack(spacing: 0) {
                    ForEach(dashboardViewModel.unpaidBills) { bill in
                        TodayBillRow(bill: bill) {
                            Task { await dashboardViewModel.toggleBillPaid(bill: bill) }
                        }
                    }
                }
            }
        }
    }

    private var recentMemorySection: some View {
        DashboardSection(title: "Recent Memory", systemImage: "tray") {
            if dashboardViewModel.recentMemoryItems.isEmpty {
                EmptyStateView(
                    title: "No recent captures",
                    message: "Notes, ideas, and links from Inbox will appear here.",
                    systemImage: "tray"
                )
                .frame(minHeight: 120)
            } else {
                VStack(spacing: 0) {
                    ForEach(dashboardViewModel.recentMemoryItems) { memory in
                        TodayMemoryRow(memory: memory) {
                            Task { await dashboardViewModel.archiveMemory(memory: memory) }
                        }
                    }
                }
            }
        }
    }

    private func createMoodCheckIn() async {
        await dashboardViewModel.createMood(
            mood: selectedMood,
            energy: selectedEnergy,
            notes: moodNotes
        )

        if dashboardViewModel.errorMessage == nil {
            moodNotes = ""
        }
    }
}

private struct DashboardSection<Content: View>: View {
    let title: String
    let systemImage: String
    var count: Int? = nil
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: OrbitSpacing.sm) {
            OrbitSectionHeader(title, systemImage: systemImage) {
                if let count {
                    OrbitBadge(text: "\(count) open")
                        .accessibilityLabel(count == 1 ? "1 open todo" : "\(count) open todos")
                }
            }
            content
        }
        .padding(.top, OrbitSpacing.xxs)
    }
}

private struct TodayTodoRow: View {
    let todo: TodoDTO
    let isHighlighted: Bool
    let isCompleting: Bool
    let projects: [ProjectDTO]
    let projectName: String?
    let isShowingProjectPicker: Bool
    let isUpdatingProject: Bool
    let projectLinkErrorMessage: String?
    let onToggle: () -> Void
    let onProjectPickerRequested: () -> Void
    let onProjectSelected: (UUID?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
                Button(action: onToggle) {
                    Group {
                        if isCompleting {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "circle")
                                .font(.title3)
                        }
                    }
                    .frame(width: 32, height: 32)
                    .foregroundStyle(isHighlighted ? Color.accentColor : .secondary)
                }
                .buttonStyle(.plain)
                .disabled(isCompleting)
                .accessibilityLabel("Complete \(todo.title)")
                .accessibilityValue(isCompleting ? "Completing" : "Not completed")

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(todo.title)

                        if isHighlighted {
                            Text("New")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(Color.accentColor)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.accentColor.opacity(0.12), in: Capsule())
                        }
                    }

                    if let urgency = TodoUrgency.resolve(dueDate: todo.dueDate) {
                        Text(urgency.label)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(urgency.tint)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(urgency.tint.opacity(0.1), in: Capsule())
                    }

                    if let projectName {
                        LinkedProjectLabel(projectName: projectName)
                    }
                }

                Spacer()

                Button(action: onProjectPickerRequested) {
                    Image(systemName: "folder")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .disabled(isUpdatingProject)
                .accessibilityLabel("Project for \(todo.title)")
            }

            if isShowingProjectPicker || projectName != nil {
                HStack(spacing: OrbitSpacing.xs) {
                    projectButton(name: "Unlinked", projectID: nil)
                    ForEach(projects) { project in
                        projectButton(name: project.name, projectID: project.id)
                    }
                }
                .padding(.leading, 44)
                .padding(.top, 4)
            }

            if let projectLinkErrorMessage {
                Label(projectLinkErrorMessage, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(.vertical, 8)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isHighlighted ? Color.accentColor.opacity(0.14) : Color.clear)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(
                    isHighlighted ? Color.accentColor.opacity(0.65) : Color.clear,
                    lineWidth: 1.5
                )
        }
        .animation(.easeInOut(duration: 0.2), value: isHighlighted)
    }

    @ViewBuilder
    private func projectButton(name: String, projectID: UUID?) -> some View {
        Button {
            onProjectSelected(projectID)
        } label: {
            if todo.projectId == projectID {
                Label(name, systemImage: "checkmark")
            } else {
                Text(name)
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
}

private struct TodayProjectDigestRow: View {
    let item: TodayProjectDigestItem
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: OrbitSpacing.xs) {
                HStack(alignment: .firstTextBaseline, spacing: OrbitSpacing.xs) {
                    Text(item.project.name)
                        .font(OrbitTypography.cardTitle)
                        .lineLimit(1)

                    Spacer(minLength: OrbitSpacing.xs)

                    OrbitBadge(text: item.project.status.capitalized, tint: statusTint)
                }

                HStack(spacing: OrbitSpacing.xs) {
                    signalLabel(
                        "\(item.openTodoCount) open",
                        systemImage: "circle",
                        accessibilityLabel: openTodoAccessibilityLabel
                    )

                    if item.completedTodoCount > 0 {
                        signalLabel(
                            "\(item.completedTodoCount) done",
                            systemImage: "checkmark.circle",
                            accessibilityLabel: completedTodoAccessibilityLabel
                        )
                    }

                    if item.memoryCount > 0 {
                        signalLabel(
                            "\(item.memoryCount) memories",
                            systemImage: "tray",
                            accessibilityLabel: memoryAccessibilityLabel
                        )
                    }
                }
                .font(OrbitTypography.caption)
                .foregroundStyle(.secondary)

                if let cue = item.nextDueCue() {
                    Text(cue)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(nextDueTint)
                        .lineLimit(1)
                } else if item.isCaughtUp {
                    Label("All caught up", systemImage: "checkmark.circle")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.green)
                        .lineLimit(1)
                }
            }
            .orbitFloatingCard(padding: OrbitSpacing.sm)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("today.projectDigest.\(item.project.name)")
    }

    private var statusTint: Color {
        switch item.project.status {
        case "active":
            .green
        case "paused":
            .orange
        case "archived":
            .secondary
        default:
            .accentColor
        }
    }

    private var nextDueTint: Color {
        TodoUrgency.resolve(dueDate: item.nextDueTodo?.dueDate)?.tint ?? .primary
    }

    private var openTodoAccessibilityLabel: String {
        item.openTodoCount == 1 ? "1 open linked todo" : "\(item.openTodoCount) open linked todos"
    }

    private var completedTodoAccessibilityLabel: String {
        item.completedTodoCount == 1
            ? "1 completed linked todo"
            : "\(item.completedTodoCount) completed linked todos"
    }

    private var memoryAccessibilityLabel: String {
        item.memoryCount == 1 ? "1 linked memory" : "\(item.memoryCount) linked memories"
    }

    private func signalLabel(
        _ text: String,
        systemImage: String,
        accessibilityLabel: String
    ) -> some View {
        Label(text, systemImage: systemImage)
            .accessibilityLabel(accessibilityLabel)
    }
}

private extension TodoUrgency {
    var tint: Color {
        switch self {
        case .overdue:
            .red
        case .today:
            .orange
        case .tomorrow, .upcoming:
            .secondary
        }
    }
}

private struct TodayBillRow: View {
    let bill: BillDTO
    let onTogglePaid: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onTogglePaid) {
                Image(systemName: "circle")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Mark paid")

            VStack(alignment: .leading, spacing: 4) {
                Text(bill.name)
                Text("Due \(bill.dueDate.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let amount = bill.amount {
                Text(amount, format: .currency(code: bill.currency))
                    .font(.subheadline.weight(.semibold))
            }
        }
        .padding(.vertical, 8)
    }
}

private struct TodayMemoryRow: View {
    let memory: MemoryDTO
    let onArchive: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline) {
                    Text(memory.title)
                        .font(.subheadline.weight(.semibold))
                    Spacer(minLength: 8)
                    Text(kindLabel(memory.kind))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                if !memory.tags.isEmpty {
                    Text(memory.tags.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Button(action: onArchive) {
                Image(systemName: "archivebox")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Archive memory")
        }
        .padding(.vertical, 8)
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

struct TodayScreen_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            TodayScreen(
                todoAPIClient: MockTodoAPIClient(),
                billAPIClient: MockBillAPIClient(),
                memoryAPIClient: MockMemoryAPIClient(),
                moodAPIClient: MockMoodAPIClient(),
                projectAPIClient: MockProjectAPIClient()
            )
            .navigationTitle("Today")
            .environmentObject(AppNavigationModel())
        }
    }
}

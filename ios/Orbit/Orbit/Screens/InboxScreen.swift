import SwiftUI

struct InboxScreen: View {
    @EnvironmentObject private var navigation: AppNavigationModel
    @StateObject private var memoryViewModel: MemoryListViewModel
    @State private var highlightedMemoryID: UUID?
    @State private var newTitle = ""
    @State private var newBody = ""
    @State private var newKind = "note"
    @State private var newSourceURL = ""
    @State private var newTags = ""

    private let kindOptions = ["note", "idea", "link", "project_update"]

    init(apiClient: any MemoryAPIClientProtocol = OrbitAPIClient()) {
        _memoryViewModel = StateObject(wrappedValue: MemoryListViewModel(apiClient: apiClient))
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

            Section("Captured") {
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
                    ForEach(memoryViewModel.memoryItems) { memory in
                        MemoryRow(
                            memory: memory,
                            isHighlighted: memory.id == highlightedMemoryID,
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
        }
        .task {
            await memoryViewModel.loadMemory()
            consumePendingHighlightIfLoaded()
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
    let isHighlighted: Bool
    let onArchive: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(memory.title)
                    .font(.headline)
                Spacer(minLength: 8)
                Text(kindLabel(memory.kind))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Text(memory.body)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(3)

            if let sourceUrl = memory.sourceUrl, !sourceUrl.isEmpty {
                Text(sourceUrl)
                    .font(.footnote)
                    .foregroundStyle(.blue)
                    .lineLimit(1)
            }

            if !memory.tags.isEmpty {
                Text(memory.tags.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
            }

            HStack {
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
        }
        .padding(.vertical, 4)
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
            InboxScreen(apiClient: MockMemoryAPIClient())
                .navigationTitle("Inbox")
                .environmentObject(AppNavigationModel())
        }
    }
}

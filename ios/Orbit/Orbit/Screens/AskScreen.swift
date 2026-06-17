import SwiftUI

struct AskScreen: View {
    @StateObject private var viewModel: AskViewModel
    @State private var isContextPreviewExpanded = false

    init(apiClient: any ChatAPIClientProtocol = OrbitAPIClient()) {
        _viewModel = StateObject(wrappedValue: AskViewModel(apiClient: apiClient))
    }

    var body: some View {
        List {
            Section {
                HStack {
                    Label("Ask Orbit", systemImage: "sparkles")
                        .font(.headline)
                    Spacer()
                    Button {
                        viewModel.startNewSession()
                    } label: {
                        Label("New", systemImage: "plus.bubble")
                    }
                    .buttonStyle(.borderless)
                }

                Toggle("Use Orbit context", isOn: $viewModel.includeContext)
            }

            if !viewModel.sessions.isEmpty {
                Section("Chats") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(viewModel.sessions) { session in
                                Button {
                                    Task { await viewModel.selectSession(session) }
                                } label: {
                                    Text(session.title ?? "Untitled")
                                        .lineLimit(1)
                                        .font(.subheadline.weight(.medium))
                                }
                                .buttonStyle(.bordered)
                                .tint(viewModel.selectedSession?.id == session.id ? .accentColor : .secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            if let errorMessage = viewModel.errorMessage {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                        Button {
                            Task { await viewModel.loadSessions() }
                        } label: {
                            Label("Retry", systemImage: "arrow.clockwise")
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            Section("Conversation") {
                if viewModel.messages.isEmpty {
                    EmptyStateView(
                        title: "Ask a question",
                        message: "Ask about your todos, bills, memory, moods, or projects.",
                        systemImage: "bubble.left.and.bubble.right"
                    )
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(viewModel.messages) { message in
                        ChatMessageRow(message: message)
                    }
                }

                if viewModel.isLoading {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                }
            }

            Section("Question") {
                TextField("Ask about your day, memory, or projects", text: $viewModel.draftQuestion, axis: .vertical)
                    .lineLimit(3...8)
                    .textInputAutocapitalization(.sentences)

                Button {
                    Task { await viewModel.sendQuestion() }
                } label: {
                    Label("Send", systemImage: "paperplane.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    viewModel.isLoading ||
                    viewModel.draftQuestion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
            }

            Section("Debug context") {
                Button {
                    Task { await viewModel.previewContext() }
                } label: {
                    Label("Preview context", systemImage: "doc.text.magnifyingglass")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(
                    viewModel.isPreviewLoading ||
                    viewModel.draftQuestion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )

                if viewModel.isPreviewLoading {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                }

                if let previewErrorMessage = viewModel.previewErrorMessage {
                    Label(previewErrorMessage, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                if let preview = viewModel.contextPreview {
                    if preview.contextSections.isEmpty {
                        Text("No context sections")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        FlowLayout(spacing: 8) {
                            ForEach(preview.contextSections, id: \.self) { section in
                                Text(section)
                                    .font(.caption.weight(.medium))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color(.secondarySystemGroupedBackground))
                                    .clipShape(Capsule())
                            }
                        }
                    }

                    DisclosureGroup("Raw context", isExpanded: $isContextPreviewExpanded) {
                        Text(preview.context.isEmpty ? "Context disabled for this preview." : preview.context)
                            .font(.footnote.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .padding(.top, 6)
                    }
                }
            }
        }
        .task {
            await viewModel.loadSessions()
        }
    }
}

private struct FlowLayout<Content: View>: View {
    var spacing: CGFloat = 8
    @ViewBuilder var content: Content

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: spacing) {
                content
            }
            VStack(alignment: .leading, spacing: spacing) {
                content
            }
        }
    }
}

private struct ChatMessageRow: View {
    let message: ChatMessageDTO

    var body: some View {
        HStack {
            if message.role == "assistant" {
                bubble
                Spacer(minLength: 32)
            } else {
                Spacer(minLength: 32)
                bubble
            }
        }
        .listRowSeparator(.hidden)
    }

    private var bubble: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(roleLabel, systemImage: roleIcon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(message.content)
                .font(.body)
                .textSelection(.enabled)
        }
        .padding(12)
        .background(message.role == "assistant" ? Color(.secondarySystemGroupedBackground) : Color.accentColor.opacity(0.14))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var roleLabel: String {
        message.role == "assistant" ? "Orbit" : "You"
    }

    private var roleIcon: String {
        message.role == "assistant" ? "sparkles" : "person.crop.circle"
    }
}

struct AskScreen_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            AskScreen(apiClient: MockChatAPIClient())
                .navigationTitle("Ask")
        }
    }
}

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
                        Label("New Chat", systemImage: "plus.bubble")
                    }
                    .buttonStyle(.borderless)
                }

                Toggle("Use Orbit context", isOn: $viewModel.includeContext)

                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Hybrid memory", isOn: $viewModel.useHybridRetrieval)
                    Text("Uses vector memory retrieval for Recent memory.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .disabled(!viewModel.includeContext)

                if let diagnostics = viewModel.latestRetrievalDiagnostics {
                    RetrievalDiagnosticsLine(diagnostics: diagnostics)
                }
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

            Section("Ask") {
                TextField("Ask about your day, memory, or projects", text: $viewModel.draftQuestion, axis: .vertical)
                    .lineLimit(3...8)
                    .textInputAutocapitalization(.sentences)

                HStack(spacing: 10) {
                    Button {
                        Task { await viewModel.previewContext() }
                    } label: {
                        Label("Preview", systemImage: "doc.text.magnifyingglass")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(
                        viewModel.isPreviewLoading ||
                        viewModel.draftQuestion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )

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

            Section("Inspect context") {
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
                    VStack(alignment: .leading, spacing: 8) {
                        Label(viewModel.contextConfidence.label, systemImage: contextConfidenceIcon)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(contextConfidenceColor)

                        Text(contextSummary(for: preview))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)

                    if !preview.includeContext {
                        Label("Context is disabled for this preview.", systemImage: "eye.slash")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else if preview.contextSections.isEmpty {
                        Text("No context sections found.")
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

                    DisclosureGroup("Show raw context", isExpanded: $isContextPreviewExpanded) {
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

    private var contextConfidenceIcon: String {
        switch viewModel.contextConfidence {
        case .noContext:
            "circle"
        case .lowContext:
            "circle.lefthalf.filled"
        case .ready:
            "checkmark.circle.fill"
        }
    }

    private var contextConfidenceColor: Color {
        switch viewModel.contextConfidence {
        case .noContext:
            .secondary
        case .lowContext:
            .orange
        case .ready:
            .green
        }
    }

    private func contextSummary(for preview: AskContextPreviewResponse) -> String {
        guard preview.includeContext else {
            return "Context disabled"
        }
        let count = preview.contextSections.count
        return "\(count) context \(count == 1 ? "section" : "sections") available"
    }
}

private struct RetrievalDiagnosticsLine: View {
    let diagnostics: RetrievalDiagnostics

    var body: some View {
        Text(
            "\(diagnostics.retrievalMode.rawValue.capitalized) • " +
            "\(diagnostics.vectorResultCount) vectors • " +
            "fallback \(diagnostics.fallbackUsed ? "yes" : "no") • " +
            "\(diagnostics.contextBuildMs.formatted(.number.precision(.fractionLength(2)))) ms"
        )
        .font(.caption.monospacedDigit())
        .foregroundStyle(.secondary)
        .accessibilityLabel(
            "Retrieval mode \(diagnostics.retrievalMode.rawValue), " +
            "\(diagnostics.vectorResultCount) vector results, " +
            "fallback \(diagnostics.fallbackUsed ? "used" : "not used"), " +
            "context build \(diagnostics.contextBuildMs) milliseconds"
        )
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
        bubble
            .frame(maxWidth: .infinity, alignment: isAssistant ? .leading : .trailing)
        .listRowSeparator(.hidden)
    }

    private var bubble: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(roleLabel, systemImage: roleIcon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(isAssistant ? Color.secondary : Color.accentColor)
            Text(message.content)
                .font(.body)
                .textSelection(.enabled)
        }
        .padding(12)
        .frame(maxWidth: 360, alignment: .leading)
        .background(isAssistant ? Color(.secondarySystemGroupedBackground) : Color.accentColor.opacity(0.14))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isAssistant ? Color(.separator).opacity(0.4) : Color.accentColor.opacity(0.18))
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var isAssistant: Bool {
        message.role == "assistant"
    }

    private var roleLabel: String {
        isAssistant ? "Orbit" : "You"
    }

    private var roleIcon: String {
        isAssistant ? "sparkles" : "person.crop.circle"
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

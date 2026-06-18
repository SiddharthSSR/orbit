import SwiftUI

struct AskScreen: View {
    @StateObject private var viewModel: AskViewModel
    @State private var isContextPreviewExpanded = false
    @State private var isConfirmingClear = false

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
                                    Text(session.displayTitle())
                                        .lineLimit(1)
                                        .font(.subheadline.weight(.medium))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(
                                            viewModel.selectedSession?.id == session.id
                                                ? Color.accentColor
                                                : Color(.secondarySystemGroupedBackground)
                                        )
                                        .foregroundStyle(
                                            viewModel.selectedSession?.id == session.id
                                                ? Color.white
                                                : Color.primary
                                        )
                                        .clipShape(Capsule())
                                        .overlay {
                                            Capsule()
                                                .stroke(
                                                    viewModel.selectedSession?.id == session.id
                                                        ? Color.accentColor
                                                        : Color.secondary.opacity(0.35),
                                                    lineWidth: 1
                                                )
                                        }
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Chat: \(session.readableTitle)")
                                .accessibilityAddTraits(
                                    viewModel.selectedSession?.id == session.id ? .isSelected : []
                                )
                                .contextMenu {
                                    Button(role: .destructive) {
                                        Task { await viewModel.deleteSession(session) }
                                    } label: {
                                        Label("Delete chat", systemImage: "trash")
                                    }
                                }
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

            if let successMessage = viewModel.suggestedActionSuccessMessage {
                Section {
                    Label(successMessage, systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.green)
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

            Section {
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
                        ChatMessageRow(
                            message: message,
                            contextSummary: viewModel.contextSummary(for: message),
                            suggestedActions: viewModel.suggestedActions(for: message),
                            onSuggestedActionTapped: viewModel.selectSuggestedAction
                        )
                    }
                }

                if viewModel.isLoading {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                }
            } header: {
                HStack {
                    Text("Conversation")
                    Spacer()
                    if viewModel.selectedSession != nil {
                        Button(role: .destructive) {
                            isConfirmingClear = true
                        } label: {
                            Label("Clear chat", systemImage: "trash")
                                .font(.caption)
                        }
                        .buttonStyle(.borderless)
                        .textCase(nil)
                    }
                }
            }
            .confirmationDialog(
                "Delete this conversation?",
                isPresented: $isConfirmingClear,
                titleVisibility: .visible
            ) {
                Button("Delete conversation", role: .destructive) {
                    Task { await viewModel.clearCurrentSession() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This permanently deletes the chat and its messages.")
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
        .sheet(
            item: Binding(
                get: { viewModel.editableSuggestedActionDraft },
                set: { draft in
                    if let draft {
                        viewModel.updateEditableSuggestedActionDraft(draft)
                    } else {
                        viewModel.dismissSuggestedActionPreview()
                    }
                }
            )
        ) { presentedDraft in
            SuggestedActionPreviewSheet(
                viewModel: viewModel,
                draft: Binding(
                    get: { viewModel.editableSuggestedActionDraft ?? presentedDraft },
                    set: { updatedDraft in
                        viewModel.updateEditableSuggestedActionDraft(updatedDraft)
                    }
                )
            )
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

/// Lightweight, dependency-free rendering helper for assistant answers.
///
/// Assistant answers are inline-Markdown-ish (bold labels, links, "- " bullets,
/// "Next step:" lines). We render each line with native `AttributedString`
/// inline parsing and fall back to plain text when parsing fails. User messages
/// are never passed through this helper — they stay plain.
enum AskAnswerMarkdown {
    /// Non-empty, trimmed lines to render, preserving the answer's line structure.
    static func displayLines(from content: String) -> [String] {
        content
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// True for a "Next step:" line, which is emphasized slightly in the UI.
    static func isNextStep(_ line: String) -> Bool {
        line.lowercased().hasPrefix("next step")
    }

    /// Renders one line: converts a leading "- "/"* " bullet to "•", parses
    /// inline Markdown (bold, links), and falls back to plain text on failure.
    static func attributedLine(_ rawLine: String) -> AttributedString {
        var line = rawLine
        var bulletPrefix: AttributedString?
        if let marker = ["- ", "* "].first(where: { line.hasPrefix($0) }) {
            line = String(line.dropFirst(marker.count))
            bulletPrefix = AttributedString("•  ")
        }

        let parsed = (try? AttributedString(
            markdown: line,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .inlineOnlyPreservingWhitespace
            )
        )) ?? AttributedString(line)

        if let bulletPrefix {
            return bulletPrefix + parsed
        }
        return parsed
    }
}

private struct ChatMessageRow: View {
    let message: ChatMessageDTO
    let contextSummary: String?
    let suggestedActions: [SuggestedActionDTO]
    let onSuggestedActionTapped: (SuggestedActionDTO) -> Void

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
            messageBody
            if isAssistant, let contextSummary {
                Divider()
                Label(contextSummary, systemImage: "doc.text.magnifyingglass")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(contextSummary)
            }
            if isAssistant, !suggestedActions.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Suggested")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    FlowLayout(spacing: 6) {
                        ForEach(suggestedActions) { action in
                            Button {
                                onSuggestedActionTapped(action)
                            } label: {
                                Label(action.title, systemImage: actionIcon(for: action))
                                    .font(.caption.weight(.medium))
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .accessibilityLabel("Suggested action: \(action.title)")
                        }
                    }
                }
            }
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

    @ViewBuilder
    private var messageBody: some View {
        if isAssistant {
            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(AskAnswerMarkdown.displayLines(from: message.content).enumerated()), id: \.offset) { _, line in
                    Text(AskAnswerMarkdown.attributedLine(line))
                        .font(AskAnswerMarkdown.isNextStep(line) ? .body.weight(.semibold) : .body)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .tint(.accentColor)
            .textSelection(.enabled)
        } else {
            Text(message.content)
                .font(.body)
                .textSelection(.enabled)
        }
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

    private func actionIcon(for action: SuggestedActionDTO) -> String {
        switch action.type {
        case "review_bills":
            "creditcard"
        case "create_todo":
            "checklist"
        case "save_memory":
            "bookmark"
        default:
            "sparkles"
        }
    }
}

private struct SuggestedActionPreviewSheet: View {
    @Environment(\.dismiss) private var dismiss

    @ObservedObject var viewModel: AskViewModel
    @Binding var draft: EditableSuggestedActionDraft

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label("Local draft only — nothing will be saved yet.", systemImage: "eye")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                Section("Action") {
                    LabeledContent("Type", value: draft.actionType)
                    Text(draft.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    if let secondaryText = draft.secondaryText {
                        Text(secondaryText)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Section("Draft fields") {
                    ForEach(draft.fields) { field in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(field.label)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            if field.futureEditable {
                                TextField(
                                    field.label,
                                    text: fieldBinding(for: field),
                                    axis: .vertical
                                )
                                .lineLimit(1...5)
                                .textInputAutocapitalization(.sentences)
                                if let validationError = draft.validationError {
                                    Text(validationError)
                                        .font(.caption)
                                        .foregroundStyle(.red)
                                }
                            } else {
                                Text(field.value)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .textSelection(.enabled)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }

                Section("Validation") {
                    Label(
                        draft.validationStatus,
                        systemImage: draft.isValid ? "checkmark.circle" : "exclamationmark.circle"
                    )
                    .font(.footnote)
                    .foregroundStyle(draft.isValid ? Color.secondary : Color.red)
                    .fixedSize(horizontal: false, vertical: true)
                }

                Section {
                    if let safetyText = draft.executionSafetyText {
                        Text(safetyText)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let errorMessage = viewModel.suggestedActionErrorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Button {
                        Task { await viewModel.executeSelectedSuggestedActionDraft() }
                    } label: {
                        HStack {
                            if viewModel.isExecutingSuggestedAction {
                                ProgressView()
                            }
                            Text(draft.executionButtonTitle)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!draft.canExecute || viewModel.isExecutingSuggestedAction)
                }
                .listRowBackground(Color.clear)
            }
            .navigationTitle(draft.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func fieldBinding(for field: SuggestedActionDraftField) -> Binding<String> {
        Binding(
            get: {
                draft.fields.first(where: { $0.id == field.id })?.value ?? field.value
            },
            set: { value in
                draft.updateField(id: field.id, value: value)
            }
        )
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

import Foundation

enum AskContextConfidence: Equatable {
    case noContext
    case lowContext
    case ready

    var label: String {
        switch self {
        case .noContext:
            "No context"
        case .lowContext:
            "Low context"
        case .ready:
            "Context ready"
        }
    }
}

/// Locally persisted Ask retrieval preferences, backed by `UserDefaults`.
///
/// Defaults match the backend keyword default for a fresh install:
/// keyword mode (`useHybridRetrieval == false`), `memoryTopK == 5`,
/// `minVectorScore == 0.0`. Only the retrieval preference is stored —
/// diagnostics, drafts, and sessions are intentionally not persisted.
struct AskRetrievalPreferences {
    private enum Key {
        static let useHybridRetrieval = "ask.retrieval.useHybridRetrieval"
        static let memoryTopK = "ask.retrieval.memoryTopK"
        static let minVectorScore = "ask.retrieval.minVectorScore"
    }

    static let defaultMemoryTopK = 5
    static let defaultMinVectorScore = 0.0

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var useHybridRetrieval: Bool {
        get { defaults.bool(forKey: Key.useHybridRetrieval) }
        nonmutating set { defaults.set(newValue, forKey: Key.useHybridRetrieval) }
    }

    var memoryTopK: Int {
        get {
            defaults.object(forKey: Key.memoryTopK) == nil
                ? Self.defaultMemoryTopK
                : defaults.integer(forKey: Key.memoryTopK)
        }
        nonmutating set { defaults.set(newValue, forKey: Key.memoryTopK) }
    }

    var minVectorScore: Double {
        get {
            defaults.object(forKey: Key.minVectorScore) == nil
                ? Self.defaultMinVectorScore
                : defaults.double(forKey: Key.minVectorScore)
        }
        nonmutating set { defaults.set(newValue, forKey: Key.minVectorScore) }
    }
}

@MainActor
final class AskViewModel: ObservableObject {
    @Published private(set) var sessions: [ChatSessionDTO] = []
    @Published private(set) var selectedSession: ChatSessionDTO?
    @Published private(set) var messages: [ChatMessageDTO] = []
    @Published var draftQuestion = ""
    @Published var includeContext = true
    @Published var useHybridRetrieval: Bool {
        didSet { preferences.useHybridRetrieval = useHybridRetrieval }
    }
    @Published var memoryTopK: Int {
        didSet { preferences.memoryTopK = memoryTopK }
    }
    @Published var minVectorScore: Double {
        didSet { preferences.minVectorScore = minVectorScore }
    }
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?
    @Published private(set) var contextPreview: AskContextPreviewResponse?
    @Published private(set) var isPreviewLoading = false
    @Published var previewErrorMessage: String?
    @Published private(set) var latestRetrievalDiagnostics: RetrievalDiagnostics?

    var contextConfidence: AskContextConfidence {
        Self.contextConfidence(for: contextPreview)
    }

    private let apiClient: any ChatAPIClientProtocol
    private let preferences: AskRetrievalPreferences

    init(
        apiClient: any ChatAPIClientProtocol = OrbitAPIClient(),
        preferences: AskRetrievalPreferences = AskRetrievalPreferences()
    ) {
        self.apiClient = apiClient
        self.preferences = preferences
        // `didSet` does not fire for assignments made during init, so loading
        // the stored values here restores them without writing back.
        self.useHybridRetrieval = preferences.useHybridRetrieval
        self.memoryTopK = preferences.memoryTopK
        self.minVectorScore = preferences.minVectorScore
    }

    func loadSessions() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            sessions = try await apiClient.listChatSessions()
        } catch {
            errorMessage = readableMessage(for: error)
        }
    }

    func selectSession(_ session: ChatSessionDTO) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            selectedSession = session
            messages = try await apiClient.listMessages(sessionId: session.id)
        } catch {
            errorMessage = readableMessage(for: error)
        }
    }

    func sendQuestion() async {
        let question = draftQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let response = try await apiClient.ask(
                AskRequest(
                    question: question,
                    sessionId: selectedSession?.id,
                    includeContext: includeContext,
                    retrievalMode: retrievalMode,
                    memoryTopK: memoryTopK,
                    minVectorScore: minVectorScore
                )
            )
            selectedSession = response.session
            messages.append(response.userMessage)
            messages.append(response.assistantMessage)
            latestRetrievalDiagnostics = response.retrievalDiagnostics
            draftQuestion = ""
            upsertSession(response.session)
        } catch {
            errorMessage = readableMessage(for: error)
        }
    }

    func previewContext() async {
        let question = draftQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return }

        isPreviewLoading = true
        previewErrorMessage = nil
        defer { isPreviewLoading = false }

        do {
            contextPreview = try await apiClient.previewAskContext(
                AskContextPreviewRequest(
                    question: question,
                    includeContext: includeContext,
                    retrievalMode: retrievalMode,
                    memoryTopK: memoryTopK,
                    minVectorScore: minVectorScore
                )
            )
            latestRetrievalDiagnostics = contextPreview?.retrievalDiagnostics
        } catch {
            previewErrorMessage = readableMessage(for: error)
        }
    }

    func startNewSession() {
        selectedSession = nil
        messages = []
        draftQuestion = ""
        errorMessage = nil
        contextPreview = nil
        latestRetrievalDiagnostics = nil
        previewErrorMessage = nil
    }

    private var retrievalMode: RetrievalMode {
        useHybridRetrieval ? .hybrid : .keyword
    }

    private func upsertSession(_ session: ChatSessionDTO) {
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[index] = session
        } else {
            sessions.insert(session, at: 0)
        }
        sessions.sort { $0.updatedAt > $1.updatedAt }
    }

    private func readableMessage(for error: Error) -> String {
        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription {
            return description
        }
        return error.localizedDescription
    }

    static func contextConfidence(for preview: AskContextPreviewResponse?) -> AskContextConfidence {
        guard let preview,
              preview.includeContext,
              !preview.contextSections.isEmpty,
              !preview.context.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .noContext
        }

        let dataSections = ["Open todos", "Unpaid bills", "Recent memory", "Latest mood", "Active projects"]
        let hasUsableData = preview.contextSections.contains { section in
            dataSections.contains(section) && !sectionIsEmpty(section, in: preview.context)
        }

        return hasUsableData ? .ready : .lowContext
    }

    private static func sectionIsEmpty(_ section: String, in context: String) -> Bool {
        let lines = context.components(separatedBy: .newlines)
        guard let sectionIndex = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines) == "\(section):" }) else {
            return true
        }

        let bodyLines = lines.dropFirst(sectionIndex + 1).prefix { line in
            !line.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix(":")
        }

        return !bodyLines.contains { line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.hasPrefix("-") && trimmed != "- None"
        }
    }
}

import Foundation

@MainActor
final class AskViewModel: ObservableObject {
    @Published private(set) var sessions: [ChatSessionDTO] = []
    @Published private(set) var selectedSession: ChatSessionDTO?
    @Published private(set) var messages: [ChatMessageDTO] = []
    @Published var draftQuestion = ""
    @Published var includeContext = true
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?
    @Published private(set) var contextPreview: AskContextPreviewResponse?
    @Published private(set) var isPreviewLoading = false
    @Published var previewErrorMessage: String?

    private let apiClient: any ChatAPIClientProtocol

    init(apiClient: any ChatAPIClientProtocol = OrbitAPIClient()) {
        self.apiClient = apiClient
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
                    includeContext: includeContext
                )
            )
            selectedSession = response.session
            messages.append(response.userMessage)
            messages.append(response.assistantMessage)
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
                    includeContext: includeContext
                )
            )
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
        previewErrorMessage = nil
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
}

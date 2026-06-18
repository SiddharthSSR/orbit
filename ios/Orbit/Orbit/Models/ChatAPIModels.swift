import Foundation

struct ChatSessionDTO: Decodable, Identifiable, Hashable, Sendable {
    let id: UUID
    var title: String?
    var createdAt: Date
    var updatedAt: Date

    var readableTitle: String {
        Self.normalizedTitle(title)
    }

    func displayTitle(maxLength: Int = 40) -> String {
        let normalized = readableTitle
        guard maxLength > 1, normalized.count > maxLength else { return normalized }
        let prefix = String(normalized.prefix(maxLength - 1))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(prefix)…"
    }

    private static func normalizedTitle(_ title: String?) -> String {
        guard let title else { return "New Ask" }
        let normalized = title
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return normalized.isEmpty ? "New Ask" : normalized
    }
}

struct ChatMessageDTO: Decodable, Identifiable, Hashable, Sendable {
    let id: UUID
    var sessionId: UUID
    var role: String
    var content: String
    var createdAt: Date
}

enum RetrievalMode: String, Codable, Equatable, Sendable {
    case keyword
    case hybrid
}

struct RetrievalDiagnostics: Decodable, Equatable, Sendable {
    var retrievalMode: RetrievalMode
    var memoryTopK: Int
    var minVectorScore: Double
    var vectorAttempted: Bool
    var vectorResultCount: Int
    var vectorError: String?
    var fallbackUsed: Bool
    var contextBuildMs: Double
}

struct SuggestedActionDTO: Decodable, Identifiable, Hashable, Sendable {
    let id: String
    var type: String
    var title: String
    var subtitle: String?
    var payload: [String: String]?

    var previewTitle: String {
        switch type {
        case "review_bills":
            "Review bills"
        case "create_todo":
            "Create todo"
        case "save_memory":
            "Save to memory"
        default:
            title.isEmpty ? "Suggested action" : title
        }
    }

    var typeLabel: String {
        switch type {
        case "review_bills":
            "Review bills"
        case "create_todo":
            "Create todo"
        case "save_memory":
            "Save to memory"
        default:
            "Suggested action"
        }
    }

    var previewDescription: String {
        switch type {
        case "review_bills":
            "A future version would take you to Bills to review overdue and upcoming payments."
        case "create_todo":
            "A future version would prepare a todo draft for you to review before creating it."
        case "save_memory":
            "A future version would prepare a memory draft for you to review before saving it."
        default:
            "A future version would prepare this suggested action for your review."
        }
    }

    var sortedPayload: [(key: String, value: String)] {
        (payload ?? [:]).sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
    }
}

/// UI-only representation of a suggested action awaiting future confirmation.
/// Drafts are derived in memory from response metadata and are never persisted.
struct SuggestedActionDraft: Identifiable, Equatable, Sendable {
    let id: String
    let actionType: String
    let title: String
    let primaryText: String
    let secondaryText: String?
    let fields: [SuggestedActionDraftField]
    let confirmationTitle: String

    init(action: SuggestedActionDTO) {
        id = action.id
        actionType = action.type

        switch action.type {
        case "review_bills":
            title = "Review bills"
            primaryText = "Review the bill scope below before a future confirmation step opens Bills."
            secondaryText = "This draft is read-only because reviewing bills does not create or change a record."
            fields = Self.details(
                for: action,
                fallbackLabel: "Scope",
                fallbackValue: action.subtitle ?? action.title,
                futureEditable: false
            )
            confirmationTitle = "Confirm coming soon"
        case "create_todo":
            title = "Create todo draft"
            primaryText = "Review the suggested todo title before creating it in a future MVP."
            secondaryText = "The title will be editable when confirmation is implemented."
            fields = [
                SuggestedActionDraftField(
                    label: "Todo title",
                    value: Self.preferredValue(
                        in: action,
                        keys: ["draft_title", "todo_title", "title", "text"]
                    ),
                    futureEditable: true
                )
            ]
            confirmationTitle = "Save coming soon"
        case "save_memory":
            title = "Save memory draft"
            primaryText = "Review the suggested memory text before saving it in a future MVP."
            secondaryText = "The memory text will be editable when confirmation is implemented."
            fields = [
                SuggestedActionDraftField(
                    label: "Memory text",
                    value: Self.preferredValue(
                        in: action,
                        keys: ["memory_text", "draft_text", "text", "content", "note"]
                    ),
                    futureEditable: true
                )
            ]
            confirmationTitle = "Save coming soon"
        default:
            title = action.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "Suggested action draft"
                : action.title
            primaryText = "Review this suggested action before a future confirmation flow is implemented."
            secondaryText = "This action type is preview-only and has no execution behavior."
            fields = Self.details(
                for: action,
                fallbackLabel: "Details",
                fallbackValue: action.subtitle ?? action.title,
                futureEditable: false
            )
            confirmationTitle = "Confirm coming soon"
        }
    }

    private static func preferredValue(in action: SuggestedActionDTO, keys: [String]) -> String {
        for key in keys {
            if let value = action.payload?[key]?.trimmedNonEmpty {
                return value
            }
        }
        return action.subtitle?.trimmedNonEmpty
            ?? action.title.trimmedNonEmpty
            ?? "No draft text suggested"
    }

    private static func details(
        for action: SuggestedActionDTO,
        fallbackLabel: String,
        fallbackValue: String,
        futureEditable: Bool
    ) -> [SuggestedActionDraftField] {
        let payloadFields = action.sortedPayload.compactMap { item -> SuggestedActionDraftField? in
            guard let value = item.value.trimmedNonEmpty else { return nil }
            return SuggestedActionDraftField(
                label: item.key.replacingOccurrences(of: "_", with: " ").capitalized,
                value: value,
                futureEditable: futureEditable
            )
        }
        if !payloadFields.isEmpty {
            return payloadFields
        }
        return [
            SuggestedActionDraftField(
                label: fallbackLabel,
                value: fallbackValue.trimmedNonEmpty ?? "No details suggested",
                futureEditable: futureEditable
            )
        ]
    }
}

struct SuggestedActionDraftField: Identifiable, Equatable, Sendable {
    let label: String
    let value: String
    let futureEditable: Bool

    var id: String { label }
}

private extension String {
    var trimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct AskRequest: Encodable, Sendable {
    var question: String
    var sessionId: UUID?
    var includeContext: Bool = true
    var retrievalMode: RetrievalMode = .keyword
    var memoryTopK: Int = 5
    var minVectorScore: Double = 0.0
}

struct AskResponse: Decodable, Sendable {
    var session: ChatSessionDTO
    var userMessage: ChatMessageDTO
    var assistantMessage: ChatMessageDTO
    var answer: String
    var contextSections: [String]? = nil
    var contextSummary: String? = nil
    var suggestedActions: [SuggestedActionDTO]? = nil
    var retrievalDiagnostics: RetrievalDiagnostics? = nil
}

struct AskContextPreviewRequest: Encodable, Sendable {
    var question: String
    var includeContext: Bool = true
    var retrievalMode: RetrievalMode = .keyword
    var memoryTopK: Int = 5
    var minVectorScore: Double = 0.0
}

struct AskContextPreviewResponse: Decodable, Equatable, Sendable {
    var question: String
    var includeContext: Bool
    var context: String
    var contextSections: [String]
    var retrievalDiagnostics: RetrievalDiagnostics? = nil
}

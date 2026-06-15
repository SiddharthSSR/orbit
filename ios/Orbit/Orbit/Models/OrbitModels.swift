import Foundation

struct MemoryItem: Identifiable, Hashable {
    enum Kind: String {
        case note
        case link
        case article
        case chat
        case dailyPlan
    }

    let id: UUID
    var title: String
    var body: String
    var kind: Kind
    var tags: [String]
    var createdAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        body: String,
        kind: Kind = .note,
        tags: [String] = [],
        createdAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.kind = kind
        self.tags = tags
        self.createdAt = createdAt
    }
}

struct Todo: Identifiable, Hashable {
    let id: UUID
    var title: String
    var dueDate: Date?
    var isComplete: Bool

    init(id: UUID = UUID(), title: String, dueDate: Date? = nil, isComplete: Bool = false) {
        self.id = id
        self.title = title
        self.dueDate = dueDate
        self.isComplete = isComplete
    }
}

struct Bill: Identifiable, Hashable {
    let id: UUID
    var name: String
    var amount: Decimal?
    var dueDate: Date
    var isPaid: Bool

    init(id: UUID = UUID(), name: String, amount: Decimal? = nil, dueDate: Date, isPaid: Bool = false) {
        self.id = id
        self.name = name
        self.amount = amount
        self.dueDate = dueDate
        self.isPaid = isPaid
    }
}

struct Project: Identifiable, Hashable {
    let id: UUID
    var name: String
    var description: String
    var status: String

    init(id: UUID = UUID(), name: String, description: String, status: String = "Active") {
        self.id = id
        self.name = name
        self.description = description
        self.status = status
    }
}

struct MoodLog: Identifiable, Hashable {
    let id: UUID
    var mood: String
    var energy: Int
    var notes: String
    var loggedAt: Date

    init(id: UUID = UUID(), mood: String, energy: Int, notes: String, loggedAt: Date = .now) {
        self.id = id
        self.mood = mood
        self.energy = energy
        self.notes = notes
        self.loggedAt = loggedAt
    }
}


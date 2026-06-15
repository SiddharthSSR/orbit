import Foundation

enum SampleData {
    static let todos: [Todo] = [
        Todo(title: "Plan the day"),
        Todo(title: "Review saved links"),
        Todo(title: "Pay electricity bill", dueDate: .now.addingTimeInterval(86_400))
    ]

    static let memoryItems: [MemoryItem] = [
        MemoryItem(title: "Article to read", body: "Notes and links will land here first.", kind: .link, tags: ["inbox"]),
        MemoryItem(title: "Daily thought", body: "Capture quick context before it disappears.", tags: ["journal"])
    ]

    static let bills: [Bill] = [
        Bill(name: "Rent", amount: 1_800, dueDate: .now.addingTimeInterval(432_000)),
        Bill(name: "Internet", amount: 70, dueDate: .now.addingTimeInterval(604_800))
    ]

    static let projects: [Project] = [
        Project(name: "Orbit MVP", description: "Build the first usable personal memory loop."),
        Project(name: "Home admin", description: "Keep household reminders and recurring tasks visible.")
    ]

    static let moodLogs: [MoodLog] = [
        MoodLog(mood: "Focused", energy: 4, notes: "Good momentum this morning.")
    ]
}


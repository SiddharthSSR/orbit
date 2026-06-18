import SwiftUI

/// App-wide refresh notifications, posted after a successful local mutation so
/// other screens can reload and stay consistent without a manual refresh.
extension Notification.Name {
    /// Posted after a memory item is created, updated, archived, or deleted.
    static let orbitMemoryDidChange = Notification.Name("orbitMemoryDidChange")
    /// Posted after a todo item is created, updated, completed, or deleted.
    static let orbitTodoDidChange = Notification.Name("orbitTodoDidChange")
    /// Posted after a bill is created, marked paid/unpaid, or deleted.
    static let orbitBillsDidChange = Notification.Name("orbitBillsDidChange")
}

@main
struct OrbitApp: App {
    var body: some Scene {
        WindowGroup {
            RootTabView()
        }
    }
}


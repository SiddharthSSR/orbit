import Combine
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

/// Single entry point for the app's cross-screen refresh notifications.
///
/// View models post a change through the `post…` helpers after a successful
/// mutation; screens observe via `publisher(for:)`. Centralizing the names and
/// the `post(name:object:)` boilerplate keeps refresh behavior consistent as
/// more cross-screen state is added. The `Notification.Name` members above stay
/// as the canonical name constants for backward compatibility.
enum OrbitRefreshCenter {
    static let memoryDidChange = Notification.Name.orbitMemoryDidChange
    static let todoDidChange = Notification.Name.orbitTodoDidChange
    static let billsDidChange = Notification.Name.orbitBillsDidChange

    static func postMemoryDidChange(on center: NotificationCenter = .default) {
        center.post(name: memoryDidChange, object: nil)
    }

    static func postTodoDidChange(on center: NotificationCenter = .default) {
        center.post(name: todoDidChange, object: nil)
    }

    static func postBillsDidChange(on center: NotificationCenter = .default) {
        center.post(name: billsDidChange, object: nil)
    }

    static func publisher(
        for name: Notification.Name,
        on center: NotificationCenter = .default
    ) -> NotificationCenter.Publisher {
        center.publisher(for: name)
    }
}

@main
struct OrbitApp: App {
    var body: some Scene {
        WindowGroup {
            RootTabView()
        }
    }
}


import Combine
import Foundation
import SwiftUI

struct AppLaunchConfiguration: Equatable, Sendable {
    enum Mode: Equatable, Sendable {
        case live
        case mock
    }

    static let uiTestArgument = "--orbit-ui-tests"
    static let mockEnvironmentKey = "ORBIT_USE_MOCKS"

    let mode: Mode

    init(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        mode = arguments.contains(Self.uiTestArgument) || environment[Self.mockEnvironmentKey] == "1"
            ? .mock
            : .live
    }
}

/// Root dependency graph. Mock actors are shared across tabs so a mutation in
/// Ask is visible when Inbox or Today reloads during UI tests.
struct AppDependencies {
    let todoAPIClient: any TodoAPIClientProtocol
    let billAPIClient: any BillAPIClientProtocol
    let memoryAPIClient: any MemoryAPIClientProtocol
    let moodAPIClient: any MoodAPIClientProtocol
    let projectAPIClient: any ProjectAPIClientProtocol
    let chatAPIClient: any ChatAPIClientProtocol

    static func make(for configuration: AppLaunchConfiguration) -> AppDependencies {
        switch configuration.mode {
        case .live:
            live()
        case .mock:
            mock()
        }
    }

    static func live() -> AppDependencies {
        let client = OrbitAPIClient()
        return AppDependencies(
            todoAPIClient: client,
            billAPIClient: client,
            memoryAPIClient: client,
            moodAPIClient: client,
            projectAPIClient: client,
            chatAPIClient: client
        )
    }

    static func mock() -> AppDependencies {
        AppDependencies(
            todoAPIClient: MockTodoAPIClient(),
            billAPIClient: MockBillAPIClient(),
            memoryAPIClient: MockMemoryAPIClient(),
            moodAPIClient: MockMoodAPIClient(),
            projectAPIClient: MockProjectAPIClient(),
            chatAPIClient: MockChatAPIClient()
        )
    }
}

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
    private let dependencies = AppDependencies.make(for: AppLaunchConfiguration())

    var body: some Scene {
        WindowGroup {
            RootTabView(dependencies: dependencies)
        }
    }
}

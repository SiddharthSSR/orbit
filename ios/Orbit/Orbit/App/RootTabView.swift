import SwiftUI

enum AppTab: String, CaseIterable, Identifiable {
    case today
    case inbox
    case ask
    case projects
    case bills

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: "Today"
        case .inbox: "Inbox"
        case .ask: "Ask"
        case .projects: "Projects"
        case .bills: "Bills"
        }
    }

    var systemImage: String {
        switch self {
        case .today: "sun.max"
        case .inbox: "tray"
        case .ask: "sparkles"
        case .projects: "folder"
        case .bills: "creditcard"
        }
    }
}

enum AppHighlightTarget: Equatable {
    case memory(UUID)
    case todo(UUID)
}

/// Shared, app-wide selected-tab state so screens can navigate between tabs
/// (e.g. an Ask suggested action opening the Bills tab).
@MainActor
final class AppNavigationModel: ObservableObject {
    @Published var selectedTab: AppTab
    @Published private(set) var pendingHighlight: AppHighlightTarget?

    init(
        selectedTab: AppTab = .today,
        pendingHighlight: AppHighlightTarget? = nil
    ) {
        self.selectedTab = selectedTab
        self.pendingHighlight = pendingHighlight
    }

    func select(_ tab: AppTab) {
        selectedTab = tab
    }

    func navigate(
        to tab: AppTab,
        highlighting target: AppHighlightTarget? = nil
    ) {
        pendingHighlight = target
        selectedTab = tab
    }

    @discardableResult
    func consumeHighlight(_ target: AppHighlightTarget) -> Bool {
        guard pendingHighlight == target else { return false }
        pendingHighlight = nil
        return true
    }

    func clearHighlight() {
        pendingHighlight = nil
    }
}

struct RootTabView: View {
    @StateObject private var navigation = AppNavigationModel()
    private let dependencies: AppDependencies

    init(dependencies: AppDependencies = .live()) {
        self.dependencies = dependencies
    }

    var body: some View {
        TabView(selection: $navigation.selectedTab) {
            ForEach(AppTab.allCases) { tab in
                NavigationStack {
                    screen(for: tab)
                        .navigationTitle(tab.title)
                }
                .tabItem {
                    Label(tab.title, systemImage: tab.systemImage)
                }
                .tag(tab)
            }
        }
        .environmentObject(navigation)
    }

    @ViewBuilder
    private func screen(for tab: AppTab) -> some View {
        switch tab {
        case .today:
            TodayScreen(
                todoAPIClient: dependencies.todoAPIClient,
                billAPIClient: dependencies.billAPIClient,
                memoryAPIClient: dependencies.memoryAPIClient,
                moodAPIClient: dependencies.moodAPIClient
            )
        case .inbox:
            InboxScreen(apiClient: dependencies.memoryAPIClient)
        case .ask:
            AskScreen(
                apiClient: dependencies.chatAPIClient,
                memoryClient: dependencies.memoryAPIClient,
                todoClient: dependencies.todoAPIClient
            )
        case .projects:
            ProjectsScreen(apiClient: dependencies.projectAPIClient)
        case .bills:
            BillsScreen(apiClient: dependencies.billAPIClient)
        }
    }
}

struct RootTabView_Previews: PreviewProvider {
    static var previews: some View {
        RootTabView(dependencies: .mock())
    }
}

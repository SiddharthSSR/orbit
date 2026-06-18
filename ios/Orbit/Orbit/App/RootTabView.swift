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

/// Shared, app-wide selected-tab state so screens can navigate between tabs
/// (e.g. an Ask suggested action opening the Bills tab).
@MainActor
final class AppNavigationModel: ObservableObject {
    @Published var selectedTab: AppTab

    init(selectedTab: AppTab = .today) {
        self.selectedTab = selectedTab
    }

    func select(_ tab: AppTab) {
        selectedTab = tab
    }
}

struct RootTabView: View {
    @StateObject private var navigation = AppNavigationModel()

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
            TodayScreen()
        case .inbox:
            InboxScreen()
        case .ask:
            AskScreen()
        case .projects:
            ProjectsScreen()
        case .bills:
            BillsScreen()
        }
    }
}

struct RootTabView_Previews: PreviewProvider {
    static var previews: some View {
        RootTabView()
    }
}

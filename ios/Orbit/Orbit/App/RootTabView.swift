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

struct RootTabView: View {
    @State private var selectedTab: AppTab = .today

    var body: some View {
        TabView(selection: $selectedTab) {
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

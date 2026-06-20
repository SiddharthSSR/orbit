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
        // Keep the native TabView for content switching and per-tab state, but
        // hide its system bar and present a custom floating dock so the chrome
        // matches Orbit's warm editorial direction. `selectedTab` stays the
        // single source of truth, so programmatic navigation still works.
        TabView(selection: $navigation.selectedTab) {
            ForEach(AppTab.allCases) { tab in
                NavigationStack {
                    screen(for: tab)
                        .navigationTitle(tab.title)
                }
                .tag(tab)
                .toolbar(.hidden, for: .tabBar)
            }
        }
        .safeAreaInset(edge: .bottom) {
            OrbitFloatingDock(selection: $navigation.selectedTab)
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
            InboxScreen(
                apiClient: dependencies.memoryAPIClient,
                projectAPIClient: dependencies.projectAPIClient
            )
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

/// A restrained floating navigation dock: a deep charcoal capsule with a soft
/// shadow, compact icon+label items, and a calm highlighted active state. It
/// drives `selectedTab` directly, and each item exposes its tab title as an
/// accessibility label with a selected trait so navigation stays testable.
private struct OrbitFloatingDock: View {
    @Binding var selection: AppTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases) { tab in
                dockItem(tab)
            }
        }
        .padding(.horizontal, OrbitSpacing.xs)
        .padding(.vertical, OrbitSpacing.xxs)
        .background(
            Capsule(style: .continuous)
                .fill(OrbitColor.dock)
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.22), radius: 12, x: 0, y: 6)
        )
        // Cap the width and center so the dock stays a tidy pill on wide
        // (iPad / landscape) layouts instead of stretching edge to edge.
        .frame(maxWidth: 460)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, OrbitSpacing.md)
        .padding(.bottom, OrbitSpacing.xs)
    }

    private func dockItem(_ tab: AppTab) -> some View {
        let isSelected = selection == tab
        return Button {
            selection = tab
        } label: {
            VStack(spacing: 3) {
                Image(systemName: tab.systemImage)
                    .font(.system(size: 17, weight: .semibold))
                Text(tab.title)
                    .font(.system(size: 10, weight: .medium))
                    // Fixed compact sizing keeps the dock from breaking under
                    // large Dynamic Type; scale/clip rather than wrap or overflow.
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            // Guarantee a comfortable tap target regardless of label length.
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.vertical, OrbitSpacing.xxs)
            .foregroundStyle(
                isSelected ? Color(white: 0.98) : Color.white.opacity(0.55)
            )
            .background {
                if isSelected {
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.14))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.18), value: isSelected)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

struct RootTabView_Previews: PreviewProvider {
    static var previews: some View {
        RootTabView(dependencies: .mock())
    }
}

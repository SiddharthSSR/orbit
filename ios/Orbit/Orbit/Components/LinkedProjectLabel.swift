import SwiftUI

/// Calm, compact "Project: <name>" label shown wherever a todo or memory
/// surfaces its linked project. Centralizing it keeps linked-project visibility
/// visually consistent across Today, Inbox, and Project detail.
struct LinkedProjectLabel: View {
    let projectName: String

    var body: some View {
        Label("Project: \(projectName)", systemImage: "folder")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

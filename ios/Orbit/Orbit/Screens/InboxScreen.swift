import SwiftUI

struct InboxScreen: View {
    private let items = SampleData.memoryItems

    var body: some View {
        List {
            Section("Captured") {
                ForEach(items) { item in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.title)
                            .font(.headline)
                        Text(item.body)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if !item.tags.isEmpty {
                            Text(item.tags.joined(separator: " · "))
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .overlay {
            if items.isEmpty {
                EmptyStateView(
                    title: "Inbox is empty",
                    message: "Saved links, articles, and quick notes will appear here.",
                    systemImage: "tray"
                )
            }
        }
    }
}

struct InboxScreen_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            InboxScreen()
                .navigationTitle("Inbox")
        }
    }
}

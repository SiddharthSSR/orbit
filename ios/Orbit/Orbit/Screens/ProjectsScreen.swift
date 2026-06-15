import SwiftUI

struct ProjectsScreen: View {
    private let projects = SampleData.projects

    var body: some View {
        List {
            ForEach(projects) { project in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(project.name)
                            .font(.headline)
                        Spacer()
                        Text(project.status)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.blue.opacity(0.12))
                            .foregroundStyle(.blue)
                            .clipShape(Capsule())
                    }
                    Text(project.description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
        .overlay {
            if projects.isEmpty {
                EmptyStateView(
                    title: "No projects yet",
                    message: "Track active areas of work and connect todos to them.",
                    systemImage: "folder"
                )
            }
        }
    }
}

struct ProjectsScreen_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            ProjectsScreen()
                .navigationTitle("Projects")
        }
    }
}

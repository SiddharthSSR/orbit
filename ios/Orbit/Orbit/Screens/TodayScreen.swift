import SwiftUI

struct TodayScreen: View {
    private let todos = SampleData.todos
    private let moodLog = SampleData.moodLogs.first

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                OrbitCard {
                    Label("Daily Plan", systemImage: "calendar")
                        .font(.headline)
                    Text("Start with the most important work, then clear small admin tasks.")
                        .foregroundStyle(.secondary)
                }

                OrbitCard {
                    Label("Mood Check-in", systemImage: "heart")
                        .font(.headline)
                    if let moodLog {
                        Text("\(moodLog.mood) · Energy \(moodLog.energy)/5")
                            .font(.subheadline)
                        Text(moodLog.notes)
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Today")
                        .font(.headline)
                    ForEach(todos) { todo in
                        HStack(spacing: 12) {
                            Image(systemName: todo.isComplete ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(todo.isComplete ? .green : .secondary)
                            Text(todo.title)
                            Spacer()
                        }
                        .padding(.vertical, 8)
                    }
                }
                .padding(.top, 4)
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
    }
}

struct TodayScreen_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            TodayScreen()
                .navigationTitle("Today")
        }
    }
}

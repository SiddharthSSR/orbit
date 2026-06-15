import SwiftUI

struct AskScreen: View {
    @State private var prompt = ""

    var body: some View {
        VStack(spacing: 16) {
            OrbitCard {
                Label("Ask Orbit", systemImage: "sparkles")
                    .font(.headline)
                Text("AI chat over your personal memory will live here once the memory backend is connected.")
                    .foregroundStyle(.secondary)
            }

            TextField("Ask about your notes, plans, or projects", text: $prompt, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(3...6)

            Button {
                prompt = ""
            } label: {
                Label("Send", systemImage: "paperplane")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Spacer()
        }
        .padding()
        .background(Color(.systemGroupedBackground))
    }
}

struct AskScreen_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            AskScreen()
                .navigationTitle("Ask")
        }
    }
}

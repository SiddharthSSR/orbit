import Foundation

@MainActor
final class MoodCheckInViewModel: ObservableObject {
    @Published private(set) var moods: [MoodDTO] = []
    @Published private(set) var latestMood: MoodDTO?
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let apiClient: any MoodAPIClientProtocol

    init(apiClient: any MoodAPIClientProtocol = OrbitAPIClient()) {
        self.apiClient = apiClient
    }

    func loadMoods() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            moods = try await apiClient.listMoods(limit: 30, fromDate: nil, toDate: nil)
            latestMood = moods.first
        } catch {
            errorMessage = readableMessage(for: error)
        }
    }

    func createMood(mood: String, energy: Int, notes: String? = nil) async {
        let trimmedMood = mood.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMood.isEmpty, 1...5 ~= energy else { return }

        let trimmedNotes = notes?.trimmingCharacters(in: .whitespacesAndNewlines)
        let payload = MoodCreateRequest(
            mood: trimmedMood,
            energy: energy,
            notes: trimmedNotes?.isEmpty == true ? nil : trimmedNotes,
            checkInDate: nil
        )

        errorMessage = nil
        do {
            let createdMood = try await apiClient.createMood(payload)
            moods.insert(createdMood, at: 0)
            latestMood = createdMood
        } catch {
            errorMessage = readableMessage(for: error)
        }
    }

    func deleteMood(mood: MoodDTO) async {
        errorMessage = nil
        do {
            try await apiClient.deleteMood(id: mood.id)
            moods.removeAll { $0.id == mood.id }
            latestMood = moods.first
        } catch {
            errorMessage = readableMessage(for: error)
        }
    }

    private func readableMessage(for error: Error) -> String {
        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription {
            return description
        }
        return error.localizedDescription
    }
}

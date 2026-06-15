import Foundation

actor MockMoodAPIClient: MoodAPIClientProtocol {
    private var moods: [MoodDTO]

    init(moods: [MoodDTO] = MockMoodAPIClient.previewMoods) {
        self.moods = moods
    }

    func listMoods(limit: Int? = nil, fromDate: Date? = nil, toDate: Date? = nil) async throws -> [MoodDTO] {
        var filteredMoods = moods
        if let fromDate {
            filteredMoods = filteredMoods.filter { $0.checkInDate >= fromDate }
        }
        if let toDate {
            filteredMoods = filteredMoods.filter { $0.checkInDate <= toDate }
        }
        if let limit {
            filteredMoods = Array(filteredMoods.prefix(limit))
        }
        return filteredMoods
    }

    func createMood(_ payload: MoodCreateRequest) async throws -> MoodDTO {
        let now = Date()
        let mood = MoodDTO(
            id: UUID(),
            mood: payload.mood,
            energy: payload.energy,
            notes: payload.notes,
            checkInDate: payload.checkInDate ?? now,
            createdAt: now,
            updatedAt: now
        )
        moods.insert(mood, at: 0)
        return mood
    }

    func updateMood(id: UUID, payload: MoodUpdateRequest) async throws -> MoodDTO {
        guard let index = moods.firstIndex(where: { $0.id == id }) else {
            throw OrbitAPIError.requestFailed(statusCode: 404, message: "Mood check-in not found")
        }

        var mood = moods[index]
        if let updatedMood = payload.mood {
            mood.mood = updatedMood
        }
        if let energy = payload.energy {
            mood.energy = energy
        }
        if let notes = payload.notes {
            mood.notes = notes
        }
        if let checkInDate = payload.checkInDate {
            mood.checkInDate = checkInDate
        }
        mood.updatedAt = Date()

        moods[index] = mood
        return mood
    }

    func deleteMood(id: UUID) async throws {
        moods.removeAll { $0.id == id }
    }

    private static let previewMoods: [MoodDTO] = [
        MoodDTO(
            id: UUID(),
            mood: "focused",
            energy: 4,
            notes: "Good deep work window",
            checkInDate: Date(),
            createdAt: Date(),
            updatedAt: Date()
        ),
        MoodDTO(
            id: UUID(),
            mood: "tired",
            energy: 2,
            notes: "Need an early night",
            checkInDate: Date().addingTimeInterval(-86_400),
            createdAt: Date(),
            updatedAt: Date()
        ),
        MoodDTO(
            id: UUID(),
            mood: "calm",
            energy: 3,
            notes: nil,
            checkInDate: Date().addingTimeInterval(-172_800),
            createdAt: Date(),
            updatedAt: Date()
        )
    ]
}

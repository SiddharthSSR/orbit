import XCTest
@testable import Orbit

@MainActor
final class MoodCheckInViewModelTests: XCTestCase {
    func testLoadMoodsLoadsMockMoods() async {
        let viewModel = MoodCheckInViewModel(apiClient: MockMoodAPIClient(moods: [
            makeMood(mood: "focused", energy: 4),
            makeMood(mood: "calm", energy: 3)
        ]))

        await viewModel.loadMoods()

        XCTAssertEqual(viewModel.moods.map(\.mood), ["focused", "calm"])
        XCTAssertEqual(viewModel.latestMood?.mood, "focused")
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testCreateMoodAddsMood() async {
        let viewModel = MoodCheckInViewModel(apiClient: MockMoodAPIClient(moods: []))

        await viewModel.createMood(mood: "excited", energy: 5, notes: "Launch day")

        XCTAssertEqual(viewModel.moods.count, 1)
        XCTAssertEqual(viewModel.latestMood?.mood, "excited")
        XCTAssertEqual(viewModel.latestMood?.energy, 5)
        XCTAssertEqual(viewModel.latestMood?.notes, "Launch day")
        XCTAssertNil(viewModel.errorMessage)
    }

    func testCreateMoodRejectsBlankMood() async {
        let viewModel = MoodCheckInViewModel(apiClient: MockMoodAPIClient(moods: []))

        await viewModel.createMood(mood: "   ", energy: 3, notes: nil)

        XCTAssertTrue(viewModel.moods.isEmpty)
        XCTAssertNil(viewModel.latestMood)
    }

    func testCreateMoodRejectsInvalidEnergy() async {
        let viewModel = MoodCheckInViewModel(apiClient: MockMoodAPIClient(moods: []))

        await viewModel.createMood(mood: "focused", energy: 6, notes: nil)

        XCTAssertTrue(viewModel.moods.isEmpty)
        XCTAssertNil(viewModel.latestMood)
    }

    func testDeleteMoodRemovesMood() async {
        let mood = makeMood(mood: "tired", energy: 2)
        let viewModel = MoodCheckInViewModel(apiClient: MockMoodAPIClient(moods: [mood]))

        await viewModel.loadMoods()
        await viewModel.deleteMood(mood: mood)

        XCTAssertTrue(viewModel.moods.isEmpty)
        XCTAssertNil(viewModel.latestMood)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testErrorStateIsSetWhenAPIThrows() async {
        let viewModel = MoodCheckInViewModel(apiClient: FailingMoodAPIClient())

        await viewModel.loadMoods()

        XCTAssertEqual(viewModel.errorMessage, "Expected mood API failure.")
        XCTAssertFalse(viewModel.isLoading)
    }

    private func makeMood(mood: String, energy: Int) -> MoodDTO {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        return MoodDTO(
            id: UUID(),
            mood: mood,
            energy: energy,
            notes: nil,
            checkInDate: now,
            createdAt: now,
            updatedAt: now
        )
    }
}

private struct FailingMoodAPIClient: MoodAPIClientProtocol {
    func listMoods(limit: Int?, fromDate: Date?, toDate: Date?) async throws -> [MoodDTO] {
        throw FailingMoodAPIError.expectedFailure
    }

    func createMood(_ payload: MoodCreateRequest) async throws -> MoodDTO {
        throw FailingMoodAPIError.expectedFailure
    }

    func updateMood(id: UUID, payload: MoodUpdateRequest) async throws -> MoodDTO {
        throw FailingMoodAPIError.expectedFailure
    }

    func deleteMood(id: UUID) async throws {
        throw FailingMoodAPIError.expectedFailure
    }
}

private enum FailingMoodAPIError: LocalizedError {
    case expectedFailure

    var errorDescription: String? {
        "Expected mood API failure."
    }
}

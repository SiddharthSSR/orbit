import XCTest
@testable import Orbit

@MainActor
final class BillListViewModelTests: XCTestCase {
    func testLoadBillsLoadsMockBills() async {
        let client = MockBillAPIClient(bills: [
            makeBill(name: "Credit card"),
            makeBill(name: "Rent", isPaid: true)
        ])
        let viewModel = BillListViewModel(apiClient: client)

        await viewModel.loadBills()

        XCTAssertEqual(viewModel.bills.map(\.name), ["Credit card", "Rent"])
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testCreateBillAddsBill() async {
        let viewModel = BillListViewModel(apiClient: MockBillAPIClient(bills: []))

        await viewModel.createBill(
            name: " Internet ",
            amount: 1499,
            dueDate: makeDate(dayOffset: 2),
            notes: " Autopay "
        )

        XCTAssertEqual(viewModel.bills.count, 1)
        XCTAssertEqual(viewModel.bills.first?.name, "Internet")
        XCTAssertEqual(viewModel.bills.first?.amount, 1499)
        XCTAssertEqual(viewModel.bills.first?.currency, "INR")
        XCTAssertEqual(viewModel.bills.first?.notes, "Autopay")
        XCTAssertNil(viewModel.errorMessage)
    }

    func testCreateBillIgnoresBlankName() async {
        let viewModel = BillListViewModel(apiClient: MockBillAPIClient(bills: []))

        await viewModel.createBill(name: "   \n\t   ", amount: nil, dueDate: makeDate())

        XCTAssertTrue(viewModel.bills.isEmpty)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testToggleBillPaidFlipsStatus() async {
        let bill = makeBill(name: "Electricity")
        let viewModel = BillListViewModel(apiClient: MockBillAPIClient(bills: [bill]))

        await viewModel.loadBills()
        await viewModel.toggleBillPaid(bill: bill)

        XCTAssertEqual(viewModel.bills.first?.id, bill.id)
        XCTAssertEqual(viewModel.bills.first?.isPaid, true)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testDeleteBillRemovesBill() async {
        let bill = makeBill(name: "Water")
        let viewModel = BillListViewModel(apiClient: MockBillAPIClient(bills: [bill]))

        await viewModel.loadBills()
        await viewModel.deleteBill(bill: bill)

        XCTAssertTrue(viewModel.bills.isEmpty)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testErrorStateIsSetWhenBillAPIThrows() async {
        let viewModel = BillListViewModel(apiClient: FailingBillAPIClient())

        await viewModel.loadBills()

        XCTAssertEqual(viewModel.errorMessage, "Expected bill API failure.")
        XCTAssertFalse(viewModel.isLoading)
    }

    func testCreateToggleDeleteBillEmitBillsRefreshEvents() async {
        let center = NotificationCenter()
        let viewModel = BillListViewModel(
            apiClient: MockBillAPIClient(bills: []),
            notificationCenter: center
        )

        let createEvent = XCTNSNotificationExpectation(name: .orbitBillsDidChange, object: nil, notificationCenter: center)
        await viewModel.createBill(name: "Electricity", amount: 800, dueDate: makeDate())
        await fulfillment(of: [createEvent], timeout: 0.5)

        let created = viewModel.bills[0]
        let toggleEvent = XCTNSNotificationExpectation(name: .orbitBillsDidChange, object: nil, notificationCenter: center)
        await viewModel.toggleBillPaid(bill: created)
        await fulfillment(of: [toggleEvent], timeout: 0.5)

        let deleteEvent = XCTNSNotificationExpectation(name: .orbitBillsDidChange, object: nil, notificationCenter: center)
        await viewModel.deleteBill(bill: created)
        await fulfillment(of: [deleteEvent], timeout: 0.5)
    }

    func testFailedBillMutationDoesNotEmitRefreshEvent() async {
        let center = NotificationCenter()
        let viewModel = BillListViewModel(
            apiClient: FailingBillAPIClient(),
            notificationCenter: center
        )
        let event = XCTNSNotificationExpectation(name: .orbitBillsDidChange, object: nil, notificationCenter: center)
        event.isInverted = true

        await viewModel.createBill(name: "Will fail", amount: 100, dueDate: makeDate())

        await fulfillment(of: [event], timeout: 0.3)
    }

    func testBlankBillDoesNotEmitRefreshEvent() async {
        let center = NotificationCenter()
        let viewModel = BillListViewModel(
            apiClient: MockBillAPIClient(bills: []),
            notificationCenter: center
        )
        let event = XCTNSNotificationExpectation(name: .orbitBillsDidChange, object: nil, notificationCenter: center)
        event.isInverted = true

        await viewModel.createBill(name: "   ", amount: 100, dueDate: makeDate())

        await fulfillment(of: [event], timeout: 0.3)
    }

    private func makeBill(name: String, isPaid: Bool = false) -> BillDTO {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        return BillDTO(
            id: UUID(),
            name: name,
            amount: 1200,
            currency: "INR",
            dueDate: makeDate(),
            recurrence: "monthly",
            isPaid: isPaid,
            reminderDaysBefore: 3,
            notes: nil,
            createdAt: now,
            updatedAt: now
        )
    }

    private func makeDate(dayOffset: Int = 0) -> Date {
        Date(timeIntervalSince1970: 1_700_000_000 + TimeInterval(dayOffset * 86_400))
    }
}

@MainActor
final class OrbitRefreshCenterTests: XCTestCase {
    func testHelperNamesMatchNotificationNameConstants() {
        XCTAssertEqual(OrbitRefreshCenter.memoryDidChange, .orbitMemoryDidChange)
        XCTAssertEqual(OrbitRefreshCenter.todoDidChange, .orbitTodoDidChange)
        XCTAssertEqual(OrbitRefreshCenter.billsDidChange, .orbitBillsDidChange)
    }

    func testPostHelpersPostExpectedNamesOnGivenCenter() async {
        let center = NotificationCenter()

        let memory = XCTNSNotificationExpectation(name: .orbitMemoryDidChange, object: nil, notificationCenter: center)
        OrbitRefreshCenter.postMemoryDidChange(on: center)
        await fulfillment(of: [memory], timeout: 0.3)

        let todo = XCTNSNotificationExpectation(name: .orbitTodoDidChange, object: nil, notificationCenter: center)
        OrbitRefreshCenter.postTodoDidChange(on: center)
        await fulfillment(of: [todo], timeout: 0.3)

        let bills = XCTNSNotificationExpectation(name: .orbitBillsDidChange, object: nil, notificationCenter: center)
        OrbitRefreshCenter.postBillsDidChange(on: center)
        await fulfillment(of: [bills], timeout: 0.3)
    }

    func testPublisherObservesPostedEvent() async {
        let center = NotificationCenter()
        let expectation = XCTNSNotificationExpectation(name: .orbitBillsDidChange, object: nil, notificationCenter: center)

        OrbitRefreshCenter.postBillsDidChange(on: center)

        await fulfillment(of: [expectation], timeout: 0.3)
    }
}

private struct FailingBillAPIClient: BillAPIClientProtocol {
    func listBills() async throws -> [BillDTO] {
        throw FailingBillAPIError.expectedFailure
    }

    func createBill(_ payload: BillCreateRequest) async throws -> BillDTO {
        throw FailingBillAPIError.expectedFailure
    }

    func updateBill(id: UUID, payload: BillUpdateRequest) async throws -> BillDTO {
        throw FailingBillAPIError.expectedFailure
    }

    func deleteBill(id: UUID) async throws {
        throw FailingBillAPIError.expectedFailure
    }
}

private enum FailingBillAPIError: LocalizedError {
    case expectedFailure

    var errorDescription: String? {
        "Expected bill API failure."
    }
}

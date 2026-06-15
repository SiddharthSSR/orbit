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

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

final class BillStatusTests: XCTestCase {
    // A fixed "now" so day-based comparisons are deterministic regardless of
    // when the suite runs. Use a UTC calendar to match the fixed reference.
    private let now = Date(timeIntervalSince1970: 1_700_000_000) // 2023-11-14T22:13:20Z
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func due(daysFromNow days: Int) -> Date {
        calendar.date(byAdding: .day, value: days, to: now)!
    }

    private func resolve(
        isPaid: Bool = false,
        daysFromNow: Int,
        reminderDaysBefore: Int = 3
    ) -> BillStatus {
        BillStatus.resolve(
            isPaid: isPaid,
            dueDate: due(daysFromNow: daysFromNow),
            reminderDaysBefore: reminderDaysBefore,
            now: now,
            calendar: calendar
        )
    }

    func testPaidAlwaysWinsEvenWhenOverdue() {
        XCTAssertEqual(resolve(isPaid: true, daysFromNow: -10), .paid)
    }

    func testOverdueWhenUnpaidAndPastDue() {
        XCTAssertEqual(resolve(daysFromNow: -1), .overdue)
    }

    func testDueTodayWhenUnpaidAndDueSameCalendarDay() {
        // Due earlier in the same calendar day still reads as "Due today"
        // because the status compares whole days, not instants.
        let startOfToday = calendar.startOfDay(for: now)
        XCTAssertEqual(
            BillStatus.resolve(
                isPaid: false,
                dueDate: startOfToday,
                reminderDaysBefore: 3,
                now: now,
                calendar: calendar
            ),
            .dueToday
        )
    }

    func testDueSoonWithinReminderWindow() {
        XCTAssertEqual(resolve(daysFromNow: 2, reminderDaysBefore: 3), .dueSoon)
        // Boundary: exactly at the window edge still reads as due soon.
        XCTAssertEqual(resolve(daysFromNow: 3, reminderDaysBefore: 3), .dueSoon)
    }

    func testUpcomingBeyondReminderWindow() {
        XCTAssertEqual(resolve(daysFromNow: 4, reminderDaysBefore: 3), .upcoming)
    }

    func testFallsBackToFixedWindowWhenNoReminderLead() {
        // reminderDaysBefore <= 0 falls back to the default 3-day window.
        XCTAssertEqual(resolve(daysFromNow: 3, reminderDaysBefore: 0), .dueSoon)
        XCTAssertEqual(resolve(daysFromNow: 4, reminderDaysBefore: 0), .upcoming)
    }
}

@MainActor
final class BillUrgencyGroupingTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func bill(
        name: String,
        daysFromNow: Int,
        isPaid: Bool = false,
        reminderDaysBefore: Int = 3
    ) -> BillDTO {
        let dueDate = calendar.date(byAdding: .day, value: daysFromNow, to: now)!
        return BillDTO(
            id: UUID(),
            name: name,
            amount: 100,
            currency: "INR",
            dueDate: dueDate,
            recurrence: nil,
            isPaid: isPaid,
            reminderDaysBefore: reminderDaysBefore,
            notes: nil,
            createdAt: now,
            updatedAt: now
        )
    }

    private func group(_ bills: [BillDTO]) -> [BillGroup] {
        BillListViewModel.groupedByUrgency(bills, now: now, calendar: calendar)
    }

    func testGroupsAreOrderedMostActionableFirst() {
        let bills = [
            bill(name: "Upcoming", daysFromNow: 30),
            bill(name: "Paid", daysFromNow: -1, isPaid: true),
            bill(name: "Overdue", daysFromNow: -2),
            bill(name: "Due soon", daysFromNow: 2),
            bill(name: "Due today", daysFromNow: 0)
        ]

        let groups = group(bills)

        XCTAssertEqual(
            groups.map(\.status),
            [.overdue, .dueToday, .dueSoon, .upcoming, .paid]
        )
    }

    func testEmptyGroupsAreOmitted() {
        let bills = [
            bill(name: "Overdue", daysFromNow: -1),
            bill(name: "Upcoming", daysFromNow: 30)
        ]

        let groups = group(bills)

        // No due-today / due-soon / paid bills, so only two sections appear.
        XCTAssertEqual(groups.map(\.status), [.overdue, .upcoming])
    }

    func testWithinGroupSortsByDueDateAscending() {
        let bills = [
            bill(name: "Later", daysFromNow: 20),
            bill(name: "Sooner", daysFromNow: 10),
            bill(name: "Soonest", daysFromNow: 5)
        ]

        let upcoming = group(bills).first { $0.status == .upcoming }

        XCTAssertEqual(upcoming?.bills.map(\.name), ["Soonest", "Sooner", "Later"])
    }

    func testWithinGroupNameBreaksDueDateTies() {
        let bills = [
            bill(name: "Zebra", daysFromNow: 10),
            bill(name: "apple", daysFromNow: 10),
            bill(name: "Mango", daysFromNow: 10)
        ]

        let upcoming = group(bills).first { $0.status == .upcoming }

        // Same due date → case-insensitive name order.
        XCTAssertEqual(upcoming?.bills.map(\.name), ["apple", "Mango", "Zebra"])
    }

    func testPaidBillsAlwaysSortAfterUnpaid() {
        let bills = [
            bill(name: "Paid but overdue date", daysFromNow: -5, isPaid: true),
            bill(name: "Unpaid upcoming", daysFromNow: 30)
        ]

        let groups = group(bills)

        // Paid wins over the overdue date, so it lands in the last group.
        XCTAssertEqual(groups.map(\.status), [.upcoming, .paid])
        XCTAssertEqual(groups.last?.bills.map(\.name), ["Paid but overdue date"])
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

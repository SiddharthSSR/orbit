import Foundation

actor MockBillAPIClient: BillAPIClientProtocol {
    private var bills: [BillDTO]

    init(bills: [BillDTO] = MockBillAPIClient.previewBills) {
        self.bills = bills
    }

    func listBills() async throws -> [BillDTO] {
        bills
    }

    func createBill(_ payload: BillCreateRequest) async throws -> BillDTO {
        let now = Date()
        let bill = BillDTO(
            id: UUID(),
            name: payload.name,
            amount: payload.amount,
            currency: payload.currency,
            dueDate: payload.dueDate,
            recurrence: payload.recurrence,
            isPaid: payload.isPaid,
            reminderDaysBefore: payload.reminderDaysBefore,
            notes: payload.notes,
            createdAt: now,
            updatedAt: now
        )
        bills.insert(bill, at: 0)
        return bill
    }

    func updateBill(id: UUID, payload: BillUpdateRequest) async throws -> BillDTO {
        guard let index = bills.firstIndex(where: { $0.id == id }) else {
            throw OrbitAPIError.requestFailed(statusCode: 404, message: "Bill not found")
        }

        var bill = bills[index]
        if let name = payload.name {
            bill.name = name
        }
        if let amount = payload.amount {
            bill.amount = amount
        }
        if let currency = payload.currency {
            bill.currency = currency
        }
        if let dueDate = payload.dueDate {
            bill.dueDate = dueDate
        }
        if let recurrence = payload.recurrence {
            bill.recurrence = recurrence
        }
        if let isPaid = payload.isPaid {
            bill.isPaid = isPaid
        }
        if let reminderDaysBefore = payload.reminderDaysBefore {
            bill.reminderDaysBefore = reminderDaysBefore
        }
        if let notes = payload.notes {
            bill.notes = notes
        }
        bill.updatedAt = Date()

        bills[index] = bill
        return bill
    }

    func deleteBill(id: UUID) async throws {
        bills.removeAll { $0.id == id }
    }

    private static let previewBills: [BillDTO] = [
        BillDTO(
            id: UUID(),
            name: "Credit card bill",
            amount: 12450,
            currency: "INR",
            dueDate: Date().addingTimeInterval(172_800),
            recurrence: "monthly",
            isPaid: false,
            reminderDaysBefore: 3,
            notes: "Check statement before paying",
            createdAt: Date(),
            updatedAt: Date()
        ),
        BillDTO(
            id: UUID(),
            name: "Furlenco rent",
            amount: 2999,
            currency: "INR",
            dueDate: Date().addingTimeInterval(432_000),
            recurrence: "monthly",
            isPaid: true,
            reminderDaysBefore: 2,
            notes: nil,
            createdAt: Date(),
            updatedAt: Date()
        )
    ]
}

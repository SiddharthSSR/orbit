import Foundation

@MainActor
final class BillListViewModel: ObservableObject {
    @Published private(set) var bills: [BillDTO] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let apiClient: any BillAPIClientProtocol
    private let notificationCenter: NotificationCenter

    init(
        apiClient: any BillAPIClientProtocol = OrbitAPIClient(),
        notificationCenter: NotificationCenter = .default
    ) {
        self.apiClient = apiClient
        self.notificationCenter = notificationCenter
    }

    func loadBills(showsLoading: Bool = true) async {
        if showsLoading {
            isLoading = true
        }
        errorMessage = nil
        defer { isLoading = false }

        do {
            bills = try await apiClient.listBills()
        } catch {
            errorMessage = readableMessage(for: error)
        }
    }

    func createBill(
        name: String,
        amount: Double?,
        currency: String = "INR",
        dueDate: Date,
        recurrence: String? = nil,
        notes: String? = nil
    ) async {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        let trimmedCurrency = currency.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNotes = notes?.trimmingCharacters(in: .whitespacesAndNewlines)
        let payload = BillCreateRequest(
            name: trimmedName,
            amount: amount,
            currency: trimmedCurrency.isEmpty ? "INR" : trimmedCurrency,
            dueDate: dueDate,
            recurrence: recurrence,
            notes: trimmedNotes?.isEmpty == true ? nil : trimmedNotes
        )

        errorMessage = nil
        do {
            let bill = try await apiClient.createBill(payload)
            bills.insert(bill, at: 0)
            notificationCenter.post(name: .orbitBillsDidChange, object: nil)
        } catch {
            errorMessage = readableMessage(for: error)
        }
    }

    func toggleBillPaid(bill: BillDTO) async {
        errorMessage = nil
        do {
            let updatedBill = try await apiClient.updateBill(
                id: bill.id,
                payload: BillUpdateRequest(isPaid: !bill.isPaid)
            )
            replace(updatedBill)
            notificationCenter.post(name: .orbitBillsDidChange, object: nil)
        } catch {
            errorMessage = readableMessage(for: error)
        }
    }

    func deleteBill(bill: BillDTO) async {
        errorMessage = nil
        do {
            try await apiClient.deleteBill(id: bill.id)
            bills.removeAll { $0.id == bill.id }
            notificationCenter.post(name: .orbitBillsDidChange, object: nil)
        } catch {
            errorMessage = readableMessage(for: error)
        }
    }

    private func replace(_ bill: BillDTO) {
        guard let index = bills.firstIndex(where: { $0.id == bill.id }) else {
            bills.insert(bill, at: 0)
            return
        }
        bills[index] = bill
    }

    private func readableMessage(for error: Error) -> String {
        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription {
            return description
        }
        return error.localizedDescription
    }
}

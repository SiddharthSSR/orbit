import Foundation

/// Compact subtotal shown on a Bills group header.
enum BillGroupTotal: Equatable {
    /// Every bill in the group has an amount and they share one currency.
    case amount(Double, currency: String)
    /// Bills carry usable amounts but in more than one currency.
    case mixedCurrencies
    /// At least one bill has no amount, so a meaningful total isn't available.
    case unavailable
}

/// A run of bills that share the same urgency status, for sectioned display in
/// the Bills list. Built by `BillListViewModel.groupedByUrgency`.
struct BillGroup: Identifiable {
    let status: BillStatus
    let bills: [BillDTO]

    var id: Int { status.urgencyRank }

    /// Number of bills in the group.
    var count: Int { bills.count }

    /// Group subtotal, summed only when it is safe to do so: every bill must
    /// have an amount and all amounts must share a single currency. Otherwise a
    /// calm fallback is returned (count-only or "Mixed currencies").
    var total: BillGroupTotal {
        guard !bills.isEmpty, bills.allSatisfy({ $0.amount != nil }) else {
            return .unavailable
        }
        let currencies = Set(bills.map(\.currency))
        guard currencies.count == 1, let currency = currencies.first else {
            return .mixedCurrencies
        }
        let sum = bills.reduce(0.0) { $0 + ($1.amount ?? 0) }
        return .amount(sum, currency: currency)
    }
}

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
            OrbitRefreshCenter.postBillsDidChange(on: notificationCenter)
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
            OrbitRefreshCenter.postBillsDidChange(on: notificationCenter)
        } catch {
            errorMessage = readableMessage(for: error)
        }
    }

    func deleteBill(bill: BillDTO) async {
        errorMessage = nil
        do {
            try await apiClient.deleteBill(id: bill.id)
            bills.removeAll { $0.id == bill.id }
            OrbitRefreshCenter.postBillsDidChange(on: notificationCenter)
        } catch {
            errorMessage = readableMessage(for: error)
        }
    }

    /// Group bills into non-empty urgency sections (Overdue → Due today →
    /// Due soon → Upcoming → Paid). Within a section, bills are sorted by due
    /// date ascending, then case-insensitive name, then id for a fully stable
    /// order. `now`/`calendar` are injectable so the ordering is deterministic
    /// under test.
    static func groupedByUrgency(
        _ bills: [BillDTO],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [BillGroup] {
        BillStatus.urgencyOrder.compactMap { status in
            let matching = bills
                .filter {
                    BillStatus.resolve(
                        isPaid: $0.isPaid,
                        dueDate: $0.dueDate,
                        reminderDaysBefore: $0.reminderDaysBefore,
                        now: now,
                        calendar: calendar
                    ) == status
                }
                .sorted(by: billOrdering)
            return matching.isEmpty ? nil : BillGroup(status: status, bills: matching)
        }
    }

    /// Stable within-group ordering: due date ascending, then name, then id.
    private static func billOrdering(_ lhs: BillDTO, _ rhs: BillDTO) -> Bool {
        if lhs.dueDate != rhs.dueDate {
            return lhs.dueDate < rhs.dueDate
        }
        let nameComparison = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
        if nameComparison != .orderedSame {
            return nameComparison == .orderedAscending
        }
        return lhs.id.uuidString < rhs.id.uuidString
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

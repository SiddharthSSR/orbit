import SwiftUI

struct BillsScreen: View {
    @StateObject private var billViewModel: BillListViewModel
    @State private var newBillName = ""
    @State private var newBillAmount = ""
    @State private var newBillDueDate = Date()
    @State private var newBillNotes = ""

    init(apiClient: any BillAPIClientProtocol = OrbitAPIClient()) {
        _billViewModel = StateObject(wrappedValue: BillListViewModel(apiClient: apiClient))
    }

    var body: some View {
        List {
            Section("Add bill") {
                TextField("Name", text: $newBillName)
                    .textInputAutocapitalization(.words)

                TextField("Amount (optional)", text: $newBillAmount)
                    .keyboardType(.decimalPad)

                DatePicker("Due date", selection: $newBillDueDate, displayedComponents: .date)

                TextField("Notes (optional)", text: $newBillNotes, axis: .vertical)
                    .lineLimit(1...3)

                Button {
                    Task { await createBill() }
                } label: {
                    Label("Add bill", systemImage: "plus.circle.fill")
                }
                .disabled(newBillName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if let errorMessage = billViewModel.errorMessage {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                        Button {
                            Task { await billViewModel.loadBills() }
                        } label: {
                            Label("Retry", systemImage: "arrow.clockwise")
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            Section {
                if billViewModel.isLoading {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                } else if billViewModel.bills.isEmpty {
                    EmptyStateView(
                        title: "No bills yet",
                        message: "Payment reminders and recurring bills will show up here.",
                        systemImage: "creditcard"
                    )
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(billViewModel.bills) { bill in
                        BillRow(
                            bill: bill,
                            onTogglePaid: {
                                Task { await billViewModel.toggleBillPaid(bill: bill) }
                            },
                            onDelete: {
                                Task { await billViewModel.deleteBill(bill: bill) }
                            }
                        )
                    }
                }
            } header: {
                upcomingHeader
            }
        }
        .scrollContentBackground(.hidden)
        .orbitBackground()
        .task {
            await billViewModel.loadBills()
        }
        .onReceive(
            OrbitRefreshCenter.publisher(for: .orbitBillsDidChange)
        ) { _ in
            Task { await billViewModel.loadBills(showsLoading: false) }
        }
    }

    private var unpaidCount: Int {
        billViewModel.bills.filter { !$0.isPaid }.count
    }

    private var upcomingHeader: some View {
        OrbitSectionHeader("Upcoming payments") {
            if unpaidCount > 0 {
                OrbitBadge(text: unpaidCount == 1 ? "1 due" : "\(unpaidCount) due", tint: .orange)
            }
        }
        .textCase(nil)
    }

    private func createBill() async {
        let amount = Double(newBillAmount.trimmingCharacters(in: .whitespacesAndNewlines))
        await billViewModel.createBill(
            name: newBillName,
            amount: amount,
            dueDate: newBillDueDate,
            notes: newBillNotes
        )

        if billViewModel.errorMessage == nil {
            newBillName = ""
            newBillAmount = ""
            newBillDueDate = Date()
            newBillNotes = ""
        }
    }
}

private struct BillRow: View {
    let bill: BillDTO
    let onTogglePaid: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: OrbitSpacing.sm) {
            Button(action: onTogglePaid) {
                Image(systemName: bill.isPaid ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(bill.isPaid ? .green : .secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(bill.isPaid ? "Mark unpaid" : "Mark paid")

            VStack(alignment: .leading, spacing: OrbitSpacing.xs) {
                HStack(alignment: .firstTextBaseline) {
                    Text(bill.name)
                        .font(OrbitTypography.cardTitle)
                    Spacer(minLength: OrbitSpacing.xs)
                    OrbitBadge(text: status.label, tint: status.tint)
                }

                if let amount = bill.amount {
                    Text(amount, format: .currency(code: bill.currency))
                        .font(.title3.weight(.semibold))
                }

                Text("Due \(bill.dueDate.formatted(date: .abbreviated, time: .omitted))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if let notes = bill.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Delete bill")
        }
        .orbitFloatingCard()
        .orbitListCardRow()
    }

    private var status: BillStatus {
        BillStatus.resolve(isPaid: bill.isPaid, dueDate: bill.dueDate)
    }
}

/// Calm, status-oriented label for a bill, derived only from the existing
/// `isPaid` flag and `dueDate` (no new data fields or behavior).
private enum BillStatus {
    case paid
    case dueSoon
    case upcoming

    var label: String {
        switch self {
        case .paid: "Paid"
        case .dueSoon: "Due soon"
        case .upcoming: "Upcoming"
        }
    }

    var tint: Color {
        switch self {
        case .paid: .green
        case .dueSoon: .orange
        case .upcoming: .secondary
        }
    }

    static func resolve(isPaid: Bool, dueDate: Date) -> BillStatus {
        if isPaid { return .paid }
        let dueSoonThreshold = Calendar.current.date(byAdding: .day, value: 3, to: Date()) ?? Date()
        return dueDate <= dueSoonThreshold ? .dueSoon : .upcoming
    }
}

struct BillsScreen_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            BillsScreen(apiClient: MockBillAPIClient())
                .navigationTitle("Bills")
        }
    }
}

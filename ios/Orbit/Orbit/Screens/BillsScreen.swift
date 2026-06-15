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

            Section("Upcoming") {
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
            }
        }
        .task {
            await billViewModel.loadBills()
        }
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
        HStack(alignment: .top, spacing: 12) {
            Button(action: onTogglePaid) {
                Image(systemName: bill.isPaid ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(bill.isPaid ? .green : .secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(bill.isPaid ? "Mark unpaid" : "Mark paid")

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(bill.name)
                        .font(.headline)
                    Spacer(minLength: 8)
                    Text(bill.isPaid ? "Paid" : "Unpaid")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(bill.isPaid ? .green : .orange)
                }

                Text("Due \(bill.dueDate.formatted(date: .abbreviated, time: .omitted))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if let amount = bill.amount {
                    Text(amount, format: .currency(code: bill.currency))
                        .font(.subheadline.weight(.semibold))
                }

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
        .padding(.vertical, 4)
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

import SwiftUI

struct BillsScreen: View {
    private let bills = SampleData.bills

    var body: some View {
        List {
            Section("Upcoming") {
                ForEach(bills) { bill in
                    HStack(spacing: 12) {
                        Image(systemName: bill.isPaid ? "checkmark.circle.fill" : "clock")
                            .foregroundStyle(bill.isPaid ? .green : .orange)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(bill.name)
                                .font(.headline)
                            Text(bill.dueDate, style: .date)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let amount = bill.amount {
                            Text(amount, format: .currency(code: "USD"))
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .overlay {
            if bills.isEmpty {
                EmptyStateView(
                    title: "No bills yet",
                    message: "Payment reminders and recurring bills will show up here.",
                    systemImage: "creditcard"
                )
            }
        }
    }
}

struct BillsScreen_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            BillsScreen()
                .navigationTitle("Bills")
        }
    }
}

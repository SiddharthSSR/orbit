import SwiftUI

struct BillsScreen: View {
    @StateObject private var billViewModel: BillListViewModel
    @State private var selectedBill: BillDTO?
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

            if billViewModel.isLoading {
                Section {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                }
            } else if billViewModel.bills.isEmpty {
                Section {
                    EmptyStateView(
                        title: "No bills yet",
                        message: "Payment reminders and recurring bills will show up here.",
                        systemImage: "creditcard"
                    )
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                }
            } else {
                // Grouped most-actionable-first; empty urgency groups are omitted.
                ForEach(billGroups) { group in
                    Section {
                        ForEach(group.bills) { bill in
                            BillRow(
                                bill: bill,
                                onOpen: { selectedBill = bill },
                                onTogglePaid: {
                                    Task { await billViewModel.toggleBillPaid(bill: bill) }
                                },
                                onDelete: {
                                    Task { await billViewModel.deleteBill(bill: bill) }
                                }
                            )
                        }
                    } header: {
                        groupHeader(group)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .orbitBackground()
        .navigationDestination(item: $selectedBill) { bill in
            BillDetailView(bill: bill)
        }
        .task {
            await billViewModel.loadBills()
        }
        .onReceive(
            OrbitRefreshCenter.publisher(for: .orbitBillsDidChange)
        ) { _ in
            Task { await billViewModel.loadBills(showsLoading: false) }
        }
    }

    /// Bills grouped into non-empty urgency sections for display.
    private var billGroups: [BillGroup] {
        BillListViewModel.groupedByUrgency(billViewModel.bills)
    }

    /// Compact section header: the status label with a count badge tinted to
    /// match the status.
    private func groupHeader(_ group: BillGroup) -> some View {
        OrbitSectionHeader(group.status.label) {
            OrbitBadge(text: "\(group.bills.count)", tint: group.status.tint)
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
    let onOpen: () -> Void
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

            // Only the content area opens the read-only detail; the toggle-paid
            // and delete controls stay outside this button so their taps survive.
            Button(action: onOpen) {
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
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("Open bill \(bill.name)")
            .accessibilityHint("Opens bill details")

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
        BillStatus.resolve(
            isPaid: bill.isPaid,
            dueDate: bill.dueDate,
            reminderDaysBefore: bill.reminderDaysBefore
        )
    }
}

/// Read-only detail for a single bill (MVP-8.0). Surfaces the existing
/// `BillDTO` fields calmly — prominent amount and due date, a status badge,
/// and any optional metadata that is actually present. No editing here.
private struct BillDetailView: View {
    let bill: BillDTO

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: OrbitSpacing.md) {
                    OrbitScreenMasthead(bill.name)

                    OrbitBadge(text: status.label, tint: status.tint)

                    VStack(alignment: .leading, spacing: OrbitSpacing.xs) {
                        if let amount = bill.amount {
                            Text(amount, format: .currency(code: bill.currency))
                                .font(.largeTitle.weight(.bold))
                        } else {
                            omittedRow("No amount set", systemImage: "indianrupeesign.circle")
                        }

                        Label(
                            "Due \(bill.dueDate.formatted(date: .complete, time: .omitted))",
                            systemImage: "calendar"
                        )
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .orbitFloatingCard()
                .orbitListCardRow()
            }

            if let notes = bill.notes, !notes.isEmpty {
                Section {
                    Text(notes)
                        .font(.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .orbitFloatingCard()
                        .orbitListCardRow()
                } header: {
                    OrbitSectionHeader("Notes", systemImage: "doc.text")
                        .textCase(nil)
                }
            }

            Section {
                VStack(alignment: .leading, spacing: OrbitSpacing.sm) {
                    if let recurrence, !recurrence.isEmpty {
                        Label(recurrence.capitalized, systemImage: "arrow.triangle.2.circlepath")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        omittedRow("One-off bill", systemImage: "arrow.triangle.2.circlepath")
                    }

                    Divider()

                    Label(reminderLabel, systemImage: "bell")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Divider()

                    Label(
                        "Added \(bill.createdAt.formatted(date: .abbreviated, time: .omitted))",
                        systemImage: "clock"
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .orbitFloatingCard()
                .orbitListCardRow()
            } header: {
                OrbitSectionHeader("Details", systemImage: "info.circle")
                    .textCase(nil)
            }
        }
        .navigationTitle(bill.name)
        .navigationBarTitleDisplayMode(.inline)
        .scrollContentBackground(.hidden)
        .orbitBackground()
    }

    private var status: BillStatus {
        BillStatus.resolve(
            isPaid: bill.isPaid,
            dueDate: bill.dueDate,
            reminderDaysBefore: bill.reminderDaysBefore
        )
    }

    /// Trimmed, non-empty recurrence string or `nil`.
    private var recurrence: String? {
        guard let trimmed = bill.recurrence?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }

    private var reminderLabel: String {
        let days = bill.reminderDaysBefore
        if days <= 0 { return "No reminder" }
        return days == 1 ? "Remind 1 day before" : "Remind \(days) days before"
    }

    @ViewBuilder
    private func omittedRow(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.subheadline)
            .foregroundStyle(.tertiary)
    }
}

/// Calm, status-oriented cue for a bill, derived only from the existing
/// `isPaid` flag, `dueDate`, and `reminderDaysBefore` (no new data fields or
/// behavior). Shared verbatim by the Bills list and Bill Detail so the status
/// language stays consistent.
enum BillStatus: Equatable {
    case paid
    case overdue
    case dueToday
    case dueSoon
    case upcoming

    /// Fallback "due soon" window (in days) when a bill has no usable
    /// `reminderDaysBefore` lead time.
    static let defaultDueSoonWindowDays = 3

    /// Canonical most-actionable-first order, used for sorting and sectioning
    /// the Bills list.
    static let urgencyOrder: [BillStatus] = [.overdue, .dueToday, .dueSoon, .upcoming, .paid]

    /// Position of this status in `urgencyOrder` (lower is more urgent).
    var urgencyRank: Int {
        BillStatus.urgencyOrder.firstIndex(of: self) ?? BillStatus.urgencyOrder.count
    }

    var label: String {
        switch self {
        case .paid: "Paid"
        case .overdue: "Overdue"
        case .dueToday: "Due today"
        case .dueSoon: "Due soon"
        case .upcoming: "Upcoming"
        }
    }

    var tint: Color {
        switch self {
        case .paid: .green
        case .overdue: .red
        case .dueToday: .orange
        case .dueSoon: .orange
        case .upcoming: .secondary
        }
    }

    /// Resolve a bill's status from existing fields only, comparing whole
    /// calendar days so a bill due later today still reads as "Due today".
    /// `now` and `calendar` are injectable to keep the logic deterministic
    /// under test.
    static func resolve(
        isPaid: Bool,
        dueDate: Date,
        reminderDaysBefore: Int,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> BillStatus {
        if isPaid { return .paid }

        let today = calendar.startOfDay(for: now)
        let due = calendar.startOfDay(for: dueDate)

        if due < today { return .overdue }
        if due == today { return .dueToday }

        let window = reminderDaysBefore > 0 ? reminderDaysBefore : defaultDueSoonWindowDays
        let threshold = calendar.date(byAdding: .day, value: window, to: today) ?? today
        return due <= threshold ? .dueSoon : .upcoming
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

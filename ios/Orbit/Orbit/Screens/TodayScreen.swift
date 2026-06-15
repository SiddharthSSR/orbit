import SwiftUI

struct TodayScreen: View {
    @StateObject private var dashboardViewModel: TodayDashboardViewModel

    init(
        todoAPIClient: any TodoAPIClientProtocol = OrbitAPIClient(),
        billAPIClient: any BillAPIClientProtocol = OrbitAPIClient(),
        memoryAPIClient: any MemoryAPIClientProtocol = OrbitAPIClient()
    ) {
        _dashboardViewModel = StateObject(
            wrappedValue: TodayDashboardViewModel(
                todoAPIClient: todoAPIClient,
                billAPIClient: billAPIClient,
                memoryAPIClient: memoryAPIClient
            )
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                summaryCard

                if dashboardViewModel.isLoading {
                    loadingCard
                } else if let errorMessage = dashboardViewModel.errorMessage {
                    errorCard(errorMessage)
                } else {
                    openTodosSection
                    unpaidBillsSection
                    recentMemorySection
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .task {
            await dashboardViewModel.loadDashboard()
        }
    }

    private var summaryCard: some View {
        OrbitCard {
            Label("Daily Plan", systemImage: "calendar")
                .font(.headline)
            Text(
                "You have \(dashboardViewModel.openTodoCount) open todos, \(dashboardViewModel.unpaidBillCount) unpaid bills, and \(dashboardViewModel.recentMemoryCount) recent captures."
            )
            .foregroundStyle(.secondary)
        }
    }

    private var loadingCard: some View {
        OrbitCard {
            HStack(spacing: 10) {
                ProgressView()
                Text("Loading today")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func errorCard(_ message: String) -> some View {
        OrbitCard {
            Label("Could not load Today", systemImage: "exclamationmark.triangle")
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button {
                Task { await dashboardViewModel.loadDashboard() }
            } label: {
                Label("Retry", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
        }
    }

    private var openTodosSection: some View {
        DashboardSection(title: "Open Todos", systemImage: "checklist") {
            if dashboardViewModel.openTodos.isEmpty {
                EmptyStateView(
                    title: "No open todos",
                    message: "Completed tasks are out of the way for today.",
                    systemImage: "checkmark.circle"
                )
                .frame(minHeight: 120)
            } else {
                VStack(spacing: 0) {
                    ForEach(dashboardViewModel.openTodos) { todo in
                        TodayTodoRow(todo: todo) {
                            Task { await dashboardViewModel.toggleTodoComplete(todo: todo) }
                        }
                    }
                }
            }
        }
    }

    private var unpaidBillsSection: some View {
        DashboardSection(title: "Upcoming Bills", systemImage: "creditcard") {
            if dashboardViewModel.unpaidBills.isEmpty {
                EmptyStateView(
                    title: "No unpaid bills",
                    message: "Payment reminders are clear.",
                    systemImage: "checkmark.seal"
                )
                .frame(minHeight: 120)
            } else {
                VStack(spacing: 0) {
                    ForEach(dashboardViewModel.unpaidBills) { bill in
                        TodayBillRow(bill: bill) {
                            Task { await dashboardViewModel.toggleBillPaid(bill: bill) }
                        }
                    }
                }
            }
        }
    }

    private var recentMemorySection: some View {
        DashboardSection(title: "Recent Memory", systemImage: "tray") {
            if dashboardViewModel.recentMemoryItems.isEmpty {
                EmptyStateView(
                    title: "No recent captures",
                    message: "Notes, ideas, and links from Inbox will appear here.",
                    systemImage: "tray"
                )
                .frame(minHeight: 120)
            } else {
                VStack(spacing: 0) {
                    ForEach(dashboardViewModel.recentMemoryItems) { memory in
                        TodayMemoryRow(memory: memory) {
                            Task { await dashboardViewModel.archiveMemory(memory: memory) }
                        }
                    }
                }
            }
        }
    }
}

private struct DashboardSection<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(.headline)
            content
        }
        .padding(.top, 4)
    }
}

private struct TodayTodoRow: View {
    let todo: TodoDTO
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onToggle) {
                Image(systemName: "circle")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Mark complete")

            VStack(alignment: .leading, spacing: 4) {
                Text(todo.title)
                if let dueDate = todo.dueDate {
                    Text(dueDate, style: .date)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .padding(.vertical, 8)
    }
}

private struct TodayBillRow: View {
    let bill: BillDTO
    let onTogglePaid: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onTogglePaid) {
                Image(systemName: "circle")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Mark paid")

            VStack(alignment: .leading, spacing: 4) {
                Text(bill.name)
                Text("Due \(bill.dueDate.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let amount = bill.amount {
                Text(amount, format: .currency(code: bill.currency))
                    .font(.subheadline.weight(.semibold))
            }
        }
        .padding(.vertical, 8)
    }
}

private struct TodayMemoryRow: View {
    let memory: MemoryDTO
    let onArchive: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline) {
                    Text(memory.title)
                        .font(.subheadline.weight(.semibold))
                    Spacer(minLength: 8)
                    Text(kindLabel(memory.kind))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                if !memory.tags.isEmpty {
                    Text(memory.tags.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Button(action: onArchive) {
                Image(systemName: "archivebox")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Archive memory")
        }
        .padding(.vertical, 8)
    }

    private func kindLabel(_ kind: String) -> String {
        switch kind {
        case "project_update":
            "Project"
        default:
            kind.capitalized
        }
    }
}

struct TodayScreen_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            TodayScreen(
                todoAPIClient: MockTodoAPIClient(),
                billAPIClient: MockBillAPIClient(),
                memoryAPIClient: MockMemoryAPIClient()
            )
            .navigationTitle("Today")
        }
    }
}

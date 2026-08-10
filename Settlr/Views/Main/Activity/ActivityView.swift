import SwiftUI

enum ActivitySegment: String, CaseIterable {
    case expenses
    case income
    case savings

    var title: String {
        switch self {
        case .expenses: return "Expenses"
        case .income: return "Income"
        case .savings: return "Savings"
        }
    }
}

struct ActivityView: View {
    let workspaceId: String
    @Binding var selectedSegment: ActivitySegment
    @Binding var showExpenseForm: Bool
    @Binding var showIncomeForm: Bool
    @Binding var showSavingsForm: Bool
    let expensesVM: ExpensesVM
    let incomeVM: IncomeVM
    @Environment(AppState.self) private var appState

    private var segments: [ActivitySegment] { ActivitySegment.available(for: appState.currentUser) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // A single remaining segment is not a choice, so the control goes
                // away and the screen reads as a plain Expenses/Income/Savings list.
                if segments.count > 1 {
                    Picker("", selection: $selectedSegment) {
                        ForEach(segments, id: \.self) { segment in
                            Text(segment.title).tag(segment)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 8)
                }

                Group {
                    switch selectedSegment {
                    case .expenses:
                        ExpensesView(
                            workspaceId: workspaceId,
                            showForm: $showExpenseForm,
                            embedded: true,
                            vm: expensesVM
                        )
                    case .income:
                        IncomeView(
                            workspaceId: workspaceId,
                            showForm: $showIncomeForm,
                            embedded: true,
                            vm: incomeVM
                        )
                    case .savings:
                        SavingsView(workspaceId: workspaceId, showForm: $showSavingsForm, embedded: true)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle(selectedSegment.title)
            .navigationBarTitleDisplayMode(.large)
        }
        .preferredColorScheme(.dark)
        .onAppear(perform: reconcileSegment)
        .onChange(of: segments) { _, _ in reconcileSegment() }
    }

    /// Keeps the binding pointing at something the user is still allowed to see.
    /// The segment is owned by `MainTabView` so it survives navigation, which
    /// means it can outlive the feature that justified it.
    private func reconcileSegment() {
        guard let first = segments.first, !segments.contains(selectedSegment) else { return }
        selectedSegment = first
    }
}

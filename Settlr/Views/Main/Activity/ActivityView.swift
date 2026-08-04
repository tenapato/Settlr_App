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

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: $selectedSegment) {
                    ForEach(ActivitySegment.allCases, id: \.self) { segment in
                        Text(segment.title).tag(segment)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 24)
                .padding(.bottom, 8)

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
    }
}

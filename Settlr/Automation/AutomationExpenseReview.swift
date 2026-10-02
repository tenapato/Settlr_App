import SwiftUI

struct AutomationExpenseReview: View {
    let draft: AutomationExpenseDraft
    let workspace: WorkspaceWithRole
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var categories: [Category]?
    @State private var error: String?

    var body: some View {
        Group {
            if !(appState.currentUser?.has(.expenses) ?? false) {
                unavailable("Expenses are disabled for this account.")
            } else if let categories {
                ExpenseFormSheet(
                    workspaceId: workspace.id,
                    categories: categories,
                    automationDraft: draft,
                    automationWorkspaceName: workspace.name,
                    saveAction: { body in
                        let _: CreateExpenseResponse = try await APIClient.shared.fetch(
                            Endpoints.expenses(workspace.id), method: "POST", body: body
                        )
                    },
                    onSave: { _ in }
                )
            } else if let error {
                unavailable(error)
            } else {
                ProgressView("Preparing expense…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.bg)
            }
        }
        .task { await loadCategories() }
    }

    private func unavailable(_ message: String) -> some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "exclamationmark.circle").font(.largeTitle)
                Text(message).multilineTextAlignment(.center)
                if appState.currentUser?.has(.expenses) ?? false {
                    Button("Try Again") { Task { await loadCategories() } }
                }
                Button("Cancel") { dismiss() }
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.bg)
            .navigationTitle("Review Expense")
        }
    }

    @MainActor
    private func loadCategories() async {
        guard appState.currentUser?.has(.expenses) ?? false else { return }
        error = nil
        guard appState.currentUser?.has(.categories) ?? false else {
            categories = []
            return
        }
        do {
            let response: CategoriesResponse = try await APIClient.shared.fetch(
                Endpoints.categories(workspace.id) + "?scope=expense"
            )
            categories = response.categories
        } catch {
            self.error = error.localizedDescription
        }
    }
}

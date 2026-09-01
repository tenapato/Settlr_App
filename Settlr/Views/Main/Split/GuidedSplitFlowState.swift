import Foundation

enum GuidedSplitStep: Hashable {
    case setup
    case items
    case confirm
}

enum GuidedSplitField: Equatable {
    case merchant
    case payer
    case paymentMethod
    case total
    case items
    case reconciliation
    case onlineEdit
}

struct GuidedSplitValidationIssue: Equatable {
    let step: GuidedSplitStep
    let field: GuidedSplitField
    let message: String
}

enum SplitCardLoadState: Equatable {
    case idle
    case refreshing
    case failed(String)
}

struct GuidedSplitSubmissionSnapshot: Equatable {
    let draft: SplitDraft
    let totalEdited: Bool

    func hasUnsavedChanges(draft: SplitDraft, totalEdited: Bool, importedReceipt: Bool) -> Bool {
        importedReceipt || self.draft != draft || self.totalEdited != totalEdited
    }
}

enum GuidedSplitFlowPolicy {
    static func nextStep(splitMode: String) -> GuidedSplitStep {
        splitMode == "even" ? .confirm : .items
    }

    static func backStep(from step: GuidedSplitStep, splitMode: String) -> GuidedSplitStep {
        switch step {
        case .setup: .setup
        case .items: .setup
        case .confirm: splitMode == "even" ? .setup : .items
        }
    }

    static func firstIssue(
        on step: GuidedSplitStep,
        draft: SplitDraft,
        totalEdited: Bool,
        isEditing: Bool,
        isOnline: Bool
    ) -> GuidedSplitValidationIssue? {
        guard step == .confirm else { return nil }

        if draft.merchant.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .init(step: .setup, field: .merchant, message: "Add a merchant name.")
        }

        if draft.splitMode == "even" {
            if draft.selectedTotalCents <= 0 {
                return .init(step: .setup, field: .total, message: "Add a total greater than zero.")
            }
        } else if draft.filledItems.isEmpty {
            return .init(step: .items, field: .items, message: "Add at least one item.")
        }

        if BillSplitPayerMode(persistedValue: draft.payer) == .unavailable {
            return .init(step: .setup, field: .payer, message: "Choose who paid.")
        }

        if draft.paymentChannel == "credit_card", draft.creditCardId == nil {
            return .init(step: .setup, field: .paymentMethod, message: "Select a credit card.")
        }

        if draft.reconciliation.requiresDecision {
            return .init(step: .confirm, field: .reconciliation, message: "Resolve the total mismatch.")
        }

        if isEditing && !isOnline {
            return .init(step: .confirm, field: .onlineEdit, message: "Reconnect to save this edit.")
        }

        _ = totalEdited
        return nil
    }
}

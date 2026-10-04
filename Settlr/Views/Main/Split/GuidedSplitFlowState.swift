import Foundation

enum GuidedSplitStep: Hashable {
    case setup
    case items
    case confirm
}

enum GuidedSplitField: Hashable {
    case merchant
    case participants
    case payer
    case division
    case paymentMethod
    case total
    case items
    case item(UUID)
    case reconciliation
    case onlineEdit

    var owningStep: GuidedSplitStep {
        switch self {
        case .merchant, .participants, .payer, .division, .paymentMethod:
            .setup
        case .items, .item:
            .items
        case .total, .reconciliation, .onlineEdit:
            .confirm
        }
    }
}

struct GuidedSplitFocusRequest: Equatable {
    let field: GuidedSplitField
    fileprivate let generation: UInt
}

struct GuidedSplitFocusRequestState: Equatable {
    private var generation: UInt = 0

    mutating func request(_ field: GuidedSplitField) -> GuidedSplitFocusRequest {
        generation &+= 1
        return .init(field: field, generation: generation)
    }

    mutating func invalidate() {
        generation &+= 1
    }

    func isCurrent(_ request: GuidedSplitFocusRequest) -> Bool {
        request.generation == generation
    }
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

        if draft.splitMode != "even" {
            if draft.filledItems.isEmpty {
                return .init(step: .items, field: .items, message: "Add at least one item.")
            }
            if let invalidItem = draft.filledItems.first(where: {
                $0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }) {
                return .init(
                    step: .items,
                    field: .item(invalidItem.id),
                    message: "Add a name for this item."
                )
            }
            if let invalidItem = draft.filledItems.first(where: { $0.lineTotalCents <= 0 }) {
                return .init(
                    step: .items,
                    field: .item(invalidItem.id),
                    message: "Add a price greater than zero for this item."
                )
            }
        }

        let effectiveTotalCents = totalEdited ? draft.selectedTotalCents : draft.calculatedTotalCents
        if effectiveTotalCents <= 0 {
            return .init(step: .confirm, field: .total, message: "Add a total greater than zero.")
        }
        let effectiveReconciliation = draft.reconciliation(selectedTotalCents: effectiveTotalCents)

        if draft.participants.isEmpty {
            return .init(step: .setup, field: .participants, message: "Add at least one participant.")
        }

        if BillSplitPayerMode(persistedValue: draft.payer) == .unavailable {
            return .init(step: .setup, field: .payer, message: "Choose who paid.")
        }

        if draft.paymentChannel == "credit_card", draft.creditCardId == nil {
            return .init(step: .setup, field: .paymentMethod, message: "Select a credit card.")
        }

        if effectiveReconciliation.requiresDecision {
            return .init(step: .confirm, field: .reconciliation, message: "Resolve the total mismatch.")
        }

        if isEditing && !isOnline {
            return .init(step: .confirm, field: .onlineEdit, message: "Reconnect to save this edit.")
        }

        return nil
    }
}

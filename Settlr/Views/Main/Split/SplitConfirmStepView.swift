import SwiftUI

enum GuidedSplitPrimaryAction: Equatable {
    case create
    case saveChanges
    case saveOnPhone

    var title: String {
        switch self {
        case .create: "Create split"
        case .saveChanges: "Save changes"
        case .saveOnPhone: "Save on this phone"
        }
    }
}

/// Read-only values for the confirmation screen. Reconciliation remains owned
/// by `SplitDraft`, so the UI never creates a second tolerance policy.
struct SplitConfirmPresentation: Equatable {
    static let divisionSetupField: GuidedSplitField = .division

    let itemSubtotalCents: Int
    let taxCents: Int
    let tipCents: Int
    let feeCents: Int
    let calculatedTotalCents: Int
    let effectiveTotalCents: Int
    let receiptTotalCents: Int?
    let differenceCents: Int?
    let acknowledgementExplanation: String?
    let payerLabel: String
    let divisionSummary: String
    let paymentLabel: String
    let evenShareCents: Int?
    let offlineStatus: String?
    let requiresConnectionCheck: Bool
    let reconciliation: SplitDraft.Reconciliation

    init(draft: SplitDraft, totalEdited: Bool, isOnline: Bool = true, isEditing: Bool = false) {
        reconciliation = draft.reconciliation
        itemSubtotalCents = reconciliation.itemSubtotalCents
        taxCents = draft.taxCents
        tipCents = draft.tipCents
        feeCents = draft.feeCents
        calculatedTotalCents = reconciliation.calculatedTotalCents
        effectiveTotalCents = totalEdited ? reconciliation.selectedTotalCents : reconciliation.calculatedTotalCents
        receiptTotalCents = totalEdited ? reconciliation.selectedTotalCents : nil
        differenceCents = totalEdited && reconciliation.differenceCents != 0 ? reconciliation.differenceCents : nil
        if totalEdited && reconciliation.requiresAcknowledgement {
            acknowledgementExplanation = reconciliation.differenceCents > 0
                ? "The receipt total is higher than the calculated total. The scan likely missed a line."
                : "The receipt total is lower than the calculated total. The scan likely duplicated or overcounted a line."
        } else {
            acknowledgementExplanation = nil
        }
        switch draft.payer {
        case "me": payerLabel = "I paid it all"
        case "each_own": payerLabel = "Each paid their own"
        default: payerLabel = "Choose who paid"
        }
        paymentLabel = draft.paymentChannel == "credit_card" ? "Credit card" : "Cash / debit"
        offlineStatus = isOnline ? nil : (isEditing ? "Reconnect to save changes" : "Will save on this phone")
        requiresConnectionCheck = isEditing && !isOnline

        let people = max(1, draft.participants.count)
        if draft.splitMode == "even" {
            divisionSummary = "Evenly among \(people) \(people == 1 ? "person" : "people")"
            evenShareCents = effectiveTotalCents / people
        } else {
            divisionSummary = "By item among \(people) \(people == 1 ? "person" : "people")"
            evenShareCents = nil
        }
    }
}

struct SplitConfirmStepView: View {
    @Binding var draft: SplitDraft
    @Binding var totalEdited: Bool
    let accessibilityFocus: AccessibilityFocusState<GuidedSplitField?>.Binding
    let presentation: SplitConfirmPresentation
    let validationIssue: GuidedSplitValidationIssue?
    let onEditSetupValue: (GuidedSplitField) -> Void
    let onEditMoney: (SplitMoneyField) -> Void
    let onKeepReceiptTotal: () -> Void
    let onUseCalculatedTotal: () -> Void
    let onCheckConnection: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                SectionEyebrow("Confirm split")
                Text("Ready to split?")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Theme.ink)
                Text("Review the total and payment details before saving.")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.muted)
            }

            heroAmount
            mathRows

            if let explanation = presentation.acknowledgementExplanation {
                mismatchDecision(explanation: explanation)
            }

            summaryRows

            if let validationIssue, validationIssue.step == .confirm {
                Text(validationIssue.message)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.warning)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var heroAmount: some View {
        Button { onEditMoney(.total) } label: {
            VStack(alignment: .leading, spacing: 8) {
                Text(totalEdited ? "Receipt total" : "Calculated total")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.muted)
                HStack(alignment: .firstTextBaseline) {
                    Text(formatSplitMoney(presentation.effectiveTotalCents))
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.accentText)
                    Spacer()
                    Image(systemName: "pencil")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.muted)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Theme.line, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(totalEdited ? "Receipt" : "Calculated") total, \(formatSplitMoney(presentation.effectiveTotalCents))")
        .accessibilityFocused(accessibilityFocus, equals: .total)
    }

    private var mathRows: some View {
        FormCard {
            moneyRow("Items", presentation.itemSubtotalCents, field: nil)
            FormRowDivider()
            moneyRow("Tax", presentation.taxCents, field: .tax)
            FormRowDivider()
            moneyRow("Tip", presentation.tipCents, field: .tip)
            FormRowDivider()
            moneyRow("Fee", presentation.feeCents, field: .fee)
            FormRowDivider()
            moneyRow("Calculated total", presentation.calculatedTotalCents, field: .total, emphasized: true)
            if let receiptTotalCents = presentation.receiptTotalCents {
                FormRowDivider()
                moneyRow("Receipt total", receiptTotalCents, field: nil, emphasized: true)
            }
            if let differenceCents = presentation.differenceCents {
                FormRowDivider()
                moneyRow("Difference", differenceCents, field: nil, signed: true)
            }
        }
    }

    private func mismatchDecision(explanation: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionEyebrow("Check the receipt")
            Text(explanation)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.ink)

            HStack(spacing: 10) {
                Button("Keep receipt total", action: onKeepReceiptTotal)
                    .buttonStyle(.bordered)
                    .tint(draft.mismatchAcknowledged ? Theme.income : Theme.warning)
                    .frame(minHeight: 44)
                    .accessibilityFocused(accessibilityFocus, equals: .reconciliation)
                Button("Use calculated total", action: onUseCalculatedTotal)
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    .foregroundStyle(Theme.buttonInk)
                    .frame(minHeight: 44)
            }
            .font(.system(size: 13, weight: .semibold))

            if draft.mismatchAcknowledged {
                Text("Receipt total confirmed.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.income)
            }
        }
        .padding(16)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Theme.warning.opacity(0.4), lineWidth: 1)
        }
    }

    private var summaryRows: some View {
        FormCard {
            summaryRow("Who paid", presentation.payerLabel, field: .payer)
            FormRowDivider()
            summaryRow("Division", presentation.divisionSummary, field: SplitConfirmPresentation.divisionSetupField)
            if let evenShare = presentation.evenShareCents {
                FormRowDivider()
                staticSummaryRow("Each person", formatSplitMoney(evenShare))
            }
            FormRowDivider()
            summaryRow("Paid with", presentation.paymentLabel, field: .paymentMethod)
            if let offlineStatus = presentation.offlineStatus {
                FormRowDivider()
                if presentation.requiresConnectionCheck {
                    connectionSummaryRow(offlineStatus)
                } else {
                    staticSummaryRow("Status", offlineStatus)
                }
            }
        }
    }

    private func moneyRow(
        _ label: String,
        _ cents: Int,
        field: SplitMoneyField?,
        emphasized: Bool = false,
        signed: Bool = false
    ) -> some View {
        Group {
            if let field {
                Button { onEditMoney(field) } label: {
                    moneyRowContent(label, cents, emphasized: emphasized, editable: true, signed: signed)
                }
                    .buttonStyle(.plain)
            } else {
                moneyRowContent(label, cents, emphasized: emphasized, editable: false, signed: signed)
            }
        }
    }

    private func moneyRowContent(
        _ label: String,
        _ cents: Int,
        emphasized: Bool,
        editable: Bool,
        signed: Bool
    ) -> some View {
        HStack {
            Text(label).foregroundStyle(Theme.muted)
            Spacer()
            Text(signed ? signedMoney(cents) : formatSplitMoney(cents))
                .font(.system(size: emphasized ? 15 : 13, weight: emphasized ? .bold : .medium, design: .monospaced))
                .foregroundStyle(Theme.ink)
            if editable {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.faint)
            }
        }
        .font(.system(size: 13))
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }

    private func summaryRow(_ label: String, _ value: String, field: GuidedSplitField) -> some View {
        Button { onEditSetupValue(field) } label: { summaryRowContent(label, value, editable: true) }
            .buttonStyle(.plain)
    }

    private func staticSummaryRow(_ label: String, _ value: String) -> some View {
        summaryRowContent(label, value, editable: false)
    }

    private func connectionSummaryRow(_ status: String) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Status")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted)
                Text(status)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.ink)
            }
            Spacer(minLength: 12)
            Button("Check connection", action: onCheckConnection)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.accentText)
                .frame(minHeight: 44)
                .accessibilityFocused(accessibilityFocus, equals: .onlineEdit)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private func summaryRowContent(_ label: String, _ value: String, editable: Bool) -> some View {
        HStack {
            Text(label).foregroundStyle(Theme.muted)
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.trailing)
            if editable {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.faint)
            }
        }
        .font(.system(size: 14))
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }

    private func signedMoney(_ cents: Int) -> String {
        cents > 0 ? "+\(formatSplitMoney(cents))" : formatSplitMoney(cents)
    }
}

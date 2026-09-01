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
    let itemSubtotalCents: Int
    let taxCents: Int
    let tipCents: Int
    let feeCents: Int
    let calculatedTotalCents: Int
    let effectiveTotalCents: Int
    let differenceCents: Int?
    let payerLabel: String
    let divisionSummary: String
    let paymentLabel: String
    let evenShareCents: Int?
    let reconciliation: SplitDraft.Reconciliation

    init(draft: SplitDraft, totalEdited: Bool) {
        reconciliation = draft.reconciliation
        itemSubtotalCents = reconciliation.itemSubtotalCents
        taxCents = draft.taxCents
        tipCents = draft.tipCents
        feeCents = draft.feeCents
        calculatedTotalCents = reconciliation.calculatedTotalCents
        effectiveTotalCents = totalEdited ? reconciliation.selectedTotalCents : reconciliation.calculatedTotalCents
        differenceCents = totalEdited && reconciliation.isMaterial ? reconciliation.differenceCents : nil
        switch draft.payer {
        case "me": payerLabel = "I paid it all"
        case "each_own": payerLabel = "Each paid their own"
        default: payerLabel = "Choose who paid"
        }
        paymentLabel = draft.paymentChannel == "credit_card" ? "Credit card" : "Cash / debit"

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
    let presentation: SplitConfirmPresentation
    let primaryAction: GuidedSplitPrimaryAction
    let validationIssue: GuidedSplitValidationIssue?
    let isSubmitting: Bool
    let onEditSetupValue: (GuidedSplitField) -> Void
    let onEditMoney: (SplitMoneyField) -> Void
    let onKeepReceiptTotal: () -> Void
    let onUseCalculatedTotal: () -> Void
    let onSubmit: () -> Void

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

            if presentation.differenceCents != nil {
                mismatchDecision
            }

            summaryRows

            if let validationIssue, validationIssue.step == .confirm {
                Text(validationIssue.message)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.warning)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            SplitStickyAction(title: primaryAction.title, isSubmitting: isSubmitting, action: onSubmit)
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
        }
    }

    private var mismatchDecision: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionEyebrow("Check the receipt")
            Text("The receipt and calculated totals differ by \(signedMoney(presentation.differenceCents ?? 0)).")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.ink)

            HStack(spacing: 10) {
                Button("Keep receipt total", action: onKeepReceiptTotal)
                    .buttonStyle(.bordered)
                    .tint(draft.mismatchAcknowledged ? Theme.income : Theme.warning)
                Button("Use calculated total", action: onUseCalculatedTotal)
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    .foregroundStyle(Theme.buttonInk)
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
            summaryRow("Division", presentation.divisionSummary, field: .payer)
            if let evenShare = presentation.evenShareCents {
                FormRowDivider()
                staticSummaryRow("Each person", formatSplitMoney(evenShare))
            }
            FormRowDivider()
            summaryRow("Paid with", presentation.paymentLabel, field: .paymentMethod)
        }
    }

    private func moneyRow(_ label: String, _ cents: Int, field: SplitMoneyField?, emphasized: Bool = false) -> some View {
        Group {
            if let field {
                Button { onEditMoney(field) } label: { moneyRowContent(label, cents, emphasized: emphasized, editable: true) }
                    .buttonStyle(.plain)
            } else {
                moneyRowContent(label, cents, emphasized: emphasized, editable: false)
            }
        }
    }

    private func moneyRowContent(_ label: String, _ cents: Int, emphasized: Bool, editable: Bool) -> some View {
        HStack {
            Text(label).foregroundStyle(Theme.muted)
            Spacer()
            Text(formatSplitMoney(cents))
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
        .contentShape(Rectangle())
    }

    private func summaryRow(_ label: String, _ value: String, field: GuidedSplitField) -> some View {
        Button { onEditSetupValue(field) } label: { summaryRowContent(label, value, editable: true) }
            .buttonStyle(.plain)
    }

    private func staticSummaryRow(_ label: String, _ value: String) -> some View {
        summaryRowContent(label, value, editable: false)
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
        .contentShape(Rectangle())
    }

    private func signedMoney(_ cents: Int) -> String {
        cents > 0 ? "+\(formatSplitMoney(cents))" : formatSplitMoney(cents)
    }
}

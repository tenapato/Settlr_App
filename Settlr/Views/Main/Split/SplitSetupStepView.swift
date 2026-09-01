import SwiftUI

struct SplitSetupStepView: View {
    @Binding var draft: SplitDraft
    let totalCents: Int
    let cards: [CreditCard]
    let cardLoadState: SplitCardLoadState
    let accessibilityFocus: AccessibilityFocusState<GuidedSplitField?>.Binding
    let validationIssue: GuidedSplitValidationIssue?
    let onEditReceipt: () -> Void
    let onEditPeople: () -> Void
    let onScanAgain: () -> Void
    let onOpenParserSettings: () -> Void
    let onRetryCards: () -> Void
    let onFieldChanged: (GuidedSplitField) -> Void

    private var paymentOptions: [ToggleOption] {
        var options = [ToggleOption(value: "cash", label: "Cash / debit", icon: "banknote")]
        if !cards.isEmpty || cardLoadState != .idle || draft.paymentChannel == "credit_card" {
            options.append(ToggleOption(value: "credit_card", label: "Credit card", icon: "creditcard"))
        }
        return options
    }

    private var selectedCardLabel: String {
        guard let id = draft.creditCardId, let card = cards.first(where: { $0.id == id }) else { return "Select" }
        guard let lastFour = card.lastFour, !lastFour.isEmpty else { return card.label }
        return "\(card.label) •••• \(lastFour)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SplitReceiptHeader(
                presentation: .init(draft: draft, totalCents: totalCents),
                accessibilityFocus: accessibilityFocus,
                onEditReceipt: onEditReceipt,
                onScanAgain: onScanAgain,
                onOpenParserSettings: onOpenParserSettings
            )

            VStack(alignment: .leading, spacing: 8) {
                SectionEyebrow("Who paid?")
                payerRow(value: "me", title: "I paid it all", detail: "Track what everyone owes you", icon: "person.fill")
                    .accessibilityFocused(accessibilityFocus, equals: .payer)
                payerRow(value: "each_own", title: "Each paid their own", detail: "No one needs to pay you back", icon: "person.2.fill")
            }

            VStack(alignment: .leading, spacing: 8) {
                SectionEyebrow("How should it be divided?")
                SplitDivisionControl(
                    selection: divisionSelection,
                    accessibilityFocus: accessibilityFocus
                )
            }

            FormCard {
                SignalFormRow(label: "People", action: onEditPeople) {
                    Text("\(draft.participants.count)")
                        .font(.system(size: 15, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Theme.ink)
                }
                .accessibilityFocused(accessibilityFocus, equals: .participants)
                SignalFormRow(label: "Paid with") {
                    Menu {
                        Button("Cash / debit") {
                            onFieldChanged(.paymentMethod)
                            draft.paymentChannel = "cash"
                            draft.creditCardId = nil
                        }
                        if paymentOptions.contains(where: { $0.value == "credit_card" }) {
                            Button("Credit card") {
                                onFieldChanged(.paymentMethod)
                                draft.paymentChannel = "credit_card"
                            }
                            if draft.paymentChannel == "credit_card" {
                                ForEach(cards) { card in
                                    Button(cardLabel(card)) {
                                        onFieldChanged(.paymentMethod)
                                        draft.creditCardId = card.id
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Text(draft.paymentChannel == "credit_card" ? selectedCardLabel : "Cash / debit")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(Theme.ink)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Theme.faint)
                        }
                    }
                    .accessibilityFocused(accessibilityFocus, equals: .paymentMethod)
                }
                if case let .failed(message) = cardLoadState {
                    SignalFormRow(label: message, action: onRetryCards) {
                        Text("Retry")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.accentText)
                    }
                }
            }

            if let validationIssue, validationIssue.step == .setup {
                Text(validationIssue.message)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.warning)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func payerRow(value: String, title: String, detail: String, icon: String) -> some View {
        Button {
            onFieldChanged(.payer)
            draft.payer = value
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(draft.payer == value ? Theme.accentText : Theme.muted)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.ink)
                    Text(detail).font(.system(size: 12)).foregroundStyle(Theme.muted)
                }
                Spacer(minLength: 12)
                Image(systemName: draft.payer == value ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(draft.payer == value ? Theme.accentText : Theme.faint)
            }
            .padding(14)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(draft.payer == value ? Theme.accent.opacity(0.45) : Theme.line, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityValue(draft.payer == value ? "Selected" : "Not selected")
        .accessibilityAddTraits(draft.payer == value ? .isSelected : [])
    }

    private var divisionSelection: Binding<String> {
        Binding(
            get: { draft.splitMode },
            set: { value in
                onFieldChanged(.division)
                draft.splitMode = value
            }
        )
    }

    private func cardLabel(_ card: CreditCard) -> String {
        guard let lastFour = card.lastFour, !lastFour.isEmpty else { return card.label }
        return "\(card.label) •••• \(lastFour)"
    }
}

private struct SplitDivisionControl: View {
    @Binding var selection: String
    let accessibilityFocus: AccessibilityFocusState<GuidedSplitField?>.Binding
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 6) {
            byItemButton
            divisionButton(value: "even", label: "Evenly", icon: "equal")
        }
        .padding(5)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Theme.surface)
                .overlay {
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Theme.line, lineWidth: 1)
                }
        )
    }

    private var byItemButton: some View {
        divisionButton(value: "by_item", label: "By item", icon: "list.bullet")
            .accessibilityFocused(accessibilityFocus, equals: .division)
    }

    private func divisionButton(value: String, label: String, icon: String) -> some View {
        let isSelected = selection == value
        return Button {
            if reduceMotion {
                selection = value
            } else {
                withAnimation(.spring(duration: 0.22)) { selection = value }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                Text(label)
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(isSelected ? Theme.buttonInk : Theme.muted)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Theme.accent : Theme.surface2)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

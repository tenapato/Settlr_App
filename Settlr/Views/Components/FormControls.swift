import SwiftUI

// MARK: - Hero amount field

/// Large, centered amount entry — the focal point of the add/edit forms.
struct HeroAmountField: View {
    @Binding var amountText: String
    var tint: Color
    var focus: FocusState<Bool>.Binding
    var errorMessage: String? = nil
    var currencyCode: String = "MXN"

    var body: some View {
        VStack(spacing: 8) {
            SectionEyebrow(currencyCode, color: Theme.faint)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("$")
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .foregroundStyle(tint)

                TextField("", text: $amountText, prompt: Text("0.00").foregroundStyle(Theme.faint))
                    .focused(focus)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.center)
                    .font(.system(size: 46, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(amountText.isEmpty ? Theme.faint : Theme.ink)
                    .tint(Theme.accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.45)
                    .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: 320)

            Rectangle()
                .fill(focus.wrappedValue ? Theme.accent : Theme.line)
                .frame(maxWidth: 180, minHeight: 1, maxHeight: 1)

            if let errorMessage, !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.expense)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .frame(minHeight: 100)
        .contentShape(Rectangle())
        .onTapGesture { focus.wrappedValue = true }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Amount in Mexican pesos")
        .accessibilityValue(amountText.isEmpty ? "No amount entered" : currencyCode + " " + amountText)
    }
}

// MARK: - Signal form rows

/// Border-light, full-width form row used beneath a hero amount field.
/// The row keeps the trailing native control intact while making the complete
/// row tappable when a caller supplies an action.
struct SignalFormRow<Trailing: View>: View {
    let label: String
    let action: (() -> Void)?
    private let trailing: Trailing

    init(
        label: String,
        action: (() -> Void)? = nil,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.label = label
        self.action = action
        self.trailing = trailing()
    }

    var body: some View {
        Group {
            if let action {
                Button(action: action) { rowContent }
                    .buttonStyle(.plain)
            } else {
                rowContent
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Theme.line)
                .frame(height: 1)
        }
    }

    private var rowContent: some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.muted)
                .layoutPriority(1)

            Spacer(minLength: 16)
            trailing

            if action != nil {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.faint)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}

/// A row whose native picker/menu owns the complete hit region. Use this for
/// controls that must remain native rather than wrapping them in an inert row
/// action (which would steal focus from the control).
struct SignalNativeFormRow<Control: View>: View {
    private let control: Control

    init(@ViewBuilder control: () -> Control) {
        self.control = control()
    }

    var body: some View {
        control
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
            .accessibilityElement(children: .contain)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Theme.line)
                    .frame(height: 1)
            }
    }
}

// MARK: - Form card + rows

/// Rounded surface card that stacks field rows (mirrors TransactionDetailCard).
struct FormCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Theme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Theme.line, lineWidth: 1)
                )
        )
    }
}

/// Hairline divider between form rows (inset to align with row content).
struct FormRowDivider: View {
    var body: some View {
        Rectangle()
            .fill(Theme.line)
            .frame(height: 1)
            .padding(.leading, 16)
    }
}

/// A labeled text-input row for use inside `FormCard`.
struct FormTextRow: View {
    let label: String
    var placeholder: String = ""
    @Binding var text: String
    var focus: FocusState<Bool>.Binding? = nil

    var body: some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.muted)
                .layoutPriority(1)

            field
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 15)
    }

    @ViewBuilder
    private var field: some View {
        if let focus {
            TextField(placeholder, text: $text)
                .focused(focus)
                .autocorrectionDisabled()
        } else {
            TextField(placeholder, text: $text)
                .autocorrectionDisabled()
        }
    }
}

/// Label-left / switch-right row, with optional explanatory caption under the label.
struct FormToggleRow: View {
    let label: String
    var caption: String? = nil
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.muted)
                if let caption {
                    Text(caption)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.faint)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 16)
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(Theme.accent)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

/// Label-left / value-right row that opens a `Menu` (styled dropdown).
struct FormMenuRow<MenuContent: View>: View {
    let label: String
    let value: String
    var isPlaceholder: Bool = false
    @ViewBuilder var menu: MenuContent

    var body: some View {
        Menu {
            menu
        } label: {
            HStack(spacing: 12) {
                Text(label)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.muted)
                Spacer(minLength: 16)
                Text(value)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(isPlaceholder ? Theme.faint : Theme.ink)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.faint)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 15)
            .contentShape(Rectangle())
        }
    }
}

// MARK: - Segmented toggle

struct ToggleOption: Identifiable {
    let value: String
    let label: String
    var icon: String?
    var id: String { value }

    init(value: String, label: String, icon: String? = nil) {
        self.value = value
        self.label = label
        self.icon = icon
    }
}

/// Pill-style segmented control (accent fill on the selected segment).
struct SegmentedToggle: View {
    @Binding var selection: String
    let options: [ToggleOption]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 6) {
            ForEach(options) { opt in
                let isSelected = selection == opt.value
                Button {
                    if reduceMotion {
                        selection = opt.value
                    } else {
                        withAnimation(.spring(duration: 0.22)) { selection = opt.value }
                    }
                } label: {
                    HStack(spacing: 6) {
                        if let icon = opt.icon {
                            Image(systemName: icon)
                                .font(.system(size: 13, weight: .semibold))
                        }
                        Text(opt.label)
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundStyle(isSelected ? Theme.bg : Theme.muted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(isSelected ? Theme.accent : Theme.surface2)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(opt.label)
                .accessibilityValue(isSelected ? "Selected" : "Not selected")
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(5)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Theme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Theme.line, lineWidth: 1)
                )
        )
    }
}

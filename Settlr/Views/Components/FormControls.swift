import SwiftUI

// MARK: - Hero amount field

/// Large, centered amount entry — the focal point of the add/edit forms.
struct HeroAmountField: View {
    @Binding var amountText: String
    var tint: Color
    var focus: FocusState<Bool>.Binding

    var body: some View {
        VStack(spacing: 10) {
            SectionEyebrow("MXN", color: Theme.faint)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("$")
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .foregroundStyle(tint.opacity(0.55))

                TextField("0.00", text: $amountText)
                    .focused(focus)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.center)
                    .font(.system(size: 46, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(tint)
                    .tint(tint)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }

            Rectangle()
                .fill(Theme.line)
                .frame(width: 130, height: 1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .onTapGesture { focus.wrappedValue = true }
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

    var body: some View {
        HStack(spacing: 6) {
            ForEach(options) { opt in
                let isSelected = selection == opt.value
                Button {
                    withAnimation(.spring(duration: 0.22)) { selection = opt.value }
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

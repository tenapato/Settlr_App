import SwiftUI
import UIKit

/// Compact, non-nested shared-item toggle. The containing item row owns the
/// tap action so the whole row can be interactive without embedding a Button.
struct CompactSharedClaimControl: View {
    let presentation: SharedClaimPresentation
    var isEnabled: Bool = true
    var isLoading: Bool = false

    var body: some View {
        HStack(spacing: 7) {
            if isLoading {
                ProgressView()
                    .controlSize(.small)
                    .tint(Theme.accent)
            } else {
                Image(systemName: presentation.isSelected ? "checkmark" : "circle")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(presentation.isSelected ? Theme.accentText : Theme.muted)
            }
            Text(isLoading ? "Updating…" : presentation.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(presentation.isSelected ? Theme.accentText : Theme.muted)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(presentation.isSelected ? Theme.accent.opacity(0.08) : Color.clear)
        .overlay(
            Capsule().strokeBorder(
                presentation.isSelected ? Theme.accent.opacity(0.45) : Theme.line,
                lineWidth: 1
            )
        )
        .clipShape(Capsule())
        .opacity(isEnabled || isLoading ? 1 : 0.45)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            isLoading
                ? "Updating shared item"
                : presentation.accessibilityLabel(isEnabled: isEnabled)
        )
        .accessibilityAddTraits(isEnabled && !isLoading ? .isButton : [])
    }
}

struct ClaimSelectionCircle: View {
    let isSelected: Bool
    var isEnabled: Bool = true

    var body: some View {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(isSelected ? Theme.accentText : Theme.muted)
            .opacity(isEnabled ? 1 : 0.45)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(isEnabled ? (isSelected ? "Included" : "Add me") : "Item unavailable")
            .accessibilityAddTraits(isEnabled ? .isButton : [])
    }
}

struct CompactUnitClaimStepper: View {
    let quantity: Int
    let canDecrement: Bool
    let canIncrement: Bool
    let decrement: () -> Void
    let increment: () -> Void

    var body: some View {
        HStack(spacing: 5) {
            Button(action: decrement) {
                Image(systemName: "minus")
                    .font(.system(size: 10, weight: .bold))
                    .frame(width: 23, height: 23)
            }
            .disabled(!canDecrement)
            .accessibilityLabel("Remove one")
            .foregroundStyle(canDecrement ? Theme.accentText : Theme.faint)

            Text("\(quantity)")
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.ink)
                .frame(minWidth: 18)
                .accessibilityLabel("Mine \(quantity)")

            Button(action: increment) {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .bold))
                    .frame(width: 23, height: 23)
            }
            .disabled(!canIncrement)
            .accessibilityLabel("Add one")
            .foregroundStyle(canIncrement ? Theme.accentText : Theme.faint)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(Theme.surface2)
        .clipShape(Capsule())
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Theme tokens
//
// Single source of truth for Settlr's palette. Colors resolve against the active
// interface style so screens can follow the app-level appearance preference.

private extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

private extension Color {
    static func settlr(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

enum Theme {
    static let bg        = Color.settlr(light: 0xF3F3ED, dark: 0x090A0B)
    static let surface   = Color.settlr(light: 0xFFFFFF, dark: 0x15181B)
    static let surface2  = Color.settlr(light: 0xE9EBE4, dark: 0x1D2124)
    static let line      = Color.settlr(light: 0xDADDD6, dark: 0x2D3135)
    static let ink       = Color.settlr(light: 0x141614, dark: 0xF4F5EF)
    static let muted     = Color.settlr(light: 0x69706A, dark: 0x898F92)
    static let faint     = Color.settlr(light: 0x929890, dark: 0x5E6466)
    static let accent    = Color.settlr(light: 0xA8D522, dark: 0xCAFF3A)
    static let accentText = Color.settlr(light: 0x597500, dark: 0xCAFF3A)
    static let buttonInk = Color.settlr(light: 0x11140A, dark: 0x080A08)
    static let income    = Color.settlr(light: 0x2F7A4A, dark: 0x65D98A)
    static let expense   = Color.settlr(light: 0xB52F3A, dark: 0xFF7070)
    static let warning   = Color.settlr(light: 0x9A6500, dark: 0xFFB547)

    /// Categorical palette for charts, ordered by rank.
    static let categoryPalette: [Color] = [
        expense, warning, accent, income,
        Color.settlr(light: 0x2879A8, dark: 0x4DB8FF),
        Color.settlr(light: 0x7543A8, dark: 0xB47EF5),
    ]
    static let categoryOther = Color.settlr(light: 0xC0C4BC, dark: 0x3A3D43) // the "Otros" remainder segment
}

// MARK: - Form field surface

extension View {
    /// Rounded surface + hairline border used by form inputs.
    func formFieldStyle(verticalPadding: CGFloat = 8) -> some View {
        self
            .padding(.horizontal, 16)
            .padding(.vertical, verticalPadding)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Theme.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Theme.line, lineWidth: 1)
                    )
            )
    }
}

// MARK: - Section eyebrow

/// 11pt uppercase tracked label (matches Dashboard section headers).
struct SectionEyebrow: View {
    let text: String
    var color: Color = Theme.muted

    init(_ text: String, color: Color = Theme.muted) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(color)
            .tracking(1.4)
            .textCase(.uppercase)
    }
}

// MARK: - Day section header

/// Sticky list header for day-grouped ledgers: day label + per-day subtotal.
struct DaySectionHeader: View {
    let title: String
    let subtotalCents: Int
    var tint: Color = Theme.muted

    var body: some View {
        HStack {
            SectionEyebrow(title)
            Spacer()
            AmountLabel(cents: subtotalCents, font: .system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.bg)
    }
}

// MARK: - Primary button

/// Full-width lime CTA with press + disabled dimming.
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PrimaryButtonBody(configuration: configuration)
    }

    struct PrimaryButtonBody: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.buttonInk)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(RoundedRectangle(cornerRadius: 14).fill(Theme.accent))
                .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.4)
                .scaleEffect(configuration.isPressed ? 0.99 : 1)
                .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
        }
    }
}

import SwiftUI

// MARK: - Theme tokens
//
// Single source of truth for Settlr's palette. `Color(hex:)` is defined app-wide
// in FloatingTabBar.swift. Adopt `Theme.*` in new/redesigned UI; existing screens
// keep their inline hex calls (no app-wide migration).

enum Theme {
    static let bg        = Color(hex: "#0e0f11") // page background
    static let surface   = Color(hex: "#15171a") // cards, fields
    static let surface2  = Color(hex: "#1c1f23") // raised fills
    static let line      = Color(hex: "#2a2d32") // hairline borders / dividers
    static let ink       = Color(hex: "#ecedee") // primary text
    static let muted     = Color(hex: "#8e9197") // secondary text
    static let faint     = Color(hex: "#5a5d63") // tertiary / placeholder
    static let accent    = Color(hex: "#c8ff5a") // lime brand
    static let income    = Color(hex: "#5ddf8a") // positive
    static let expense   = Color(hex: "#ff6b6b") // negative
    static let warning   = Color(hex: "#ffb547") // caution
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
                .foregroundStyle(Theme.bg)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(RoundedRectangle(cornerRadius: 14).fill(Theme.accent))
                .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.4)
                .scaleEffect(configuration.isPressed ? 0.99 : 1)
                .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
        }
    }
}

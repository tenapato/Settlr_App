import SwiftUI
import UIKit

/// An action exposed by the global Signal launcher.
struct QuickActionItem: Identifiable {
    let id: String
    let title: String
    let subtitle: String?
    let systemImage: String
    let role: QuickActionRole
    let action: () -> Void
}

enum QuickActionRole {
    case signature
    case standard
}

private struct QuickActionLauncherPressStyle: ButtonStyle {
    let reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        let motion = QuickActionLauncherMotion(
            isOpen: false,
            isPressed: configuration.isPressed,
            reduceMotion: reduceMotion
        )

        configuration.label
            .scaleEffect(motion.scale)
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.12),
                value: configuration.isPressed
            )
    }
}

/// C6's global launcher: a lime action circle with a small, anchored satellite
/// menu. The signature item is intentionally titled “Scan and split”.
struct QuickActionLauncher: View {
    let items: [QuickActionItem]
    let isOpen: Bool
    let onSetOpen: (Bool) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @AccessibilityFocusState private var menuFocused: Bool

    private var signatureItem: QuickActionItem? {
        items.first { $0.role == .signature }
    }

    private var standardItems: [QuickActionItem] {
        items.filter { $0.role == .standard }
    }

    private var transition: AnyTransition {
        reduceMotion ? .opacity : .scale(scale: 0.82, anchor: .bottomTrailing).combined(with: .opacity)
    }

    private var launcherMotion: QuickActionLauncherMotion {
        QuickActionLauncherMotion(isOpen: isOpen, isPressed: false, reduceMotion: reduceMotion)
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if isOpen {
                Color.black.opacity(0.55)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { onSetOpen(false) }
                    .transition(.opacity)
            }

            if isOpen {
                satelliteMenu
                    .padding(.bottom, 76)
                    .transition(transition)
            }

            Button {
                let generator = UISelectionFeedbackGenerator()
                generator.prepare()
                generator.selectionChanged()
                onSetOpen(!isOpen)
            } label: {
                Image(systemName: launcherMotion.symbolName)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(isOpen ? Theme.ink : Theme.buttonInk)
                    .rotationEffect(.degrees(launcherMotion.rotationDegrees))
                    .animation(
                        reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.28, dampingFraction: 0.78),
                        value: isOpen
                    )
                    .frame(width: 58, height: 58)
                    .background(
                        Circle()
                            .fill(isOpen ? Theme.surface2 : Theme.accent)
                            .frame(width: 52, height: 52)
                    )
                    .overlay(
                        Circle()
                            .strokeBorder(Theme.accent.opacity(isOpen ? 0 : 0.35), lineWidth: 1)
                            .frame(width: 52, height: 52)
                    )
                    .shadow(color: isOpen ? .clear : Theme.accent.opacity(0.3), radius: 16, y: 4)
            }
            .buttonStyle(QuickActionLauncherPressStyle(reduceMotion: reduceMotion))
            .accessibilityLabel(isOpen ? "Close quick actions" : "Open quick actions")
            .accessibilityHint(isOpen ? "Dismisses the quick action menu" : "Shows quick actions")
            .accessibilityAddTraits(.isButton)
        }
        .onChange(of: isOpen) { _, open in
            menuFocused = open
        }
        .animation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.44, dampingFraction: 0.78), value: isOpen)
    }

    private var satelliteMenu: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let signatureItem {
                actionButton(signatureItem, isSignature: true)
            }
            ForEach(standardItems) { item in
                actionButton(item, isSignature: false)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Theme.surface)
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
                .shadow(
                    color: .black.opacity(colorScheme == .dark ? 0.55 : 0.12),
                    radius: 24,
                    y: 10
                )
        )
        .accessibilityFocused($menuFocused)
        .accessibilityElement(children: .contain)
        .accessibilityHidden(!isOpen)
    }

    @ViewBuilder
    private func actionButton(_ item: QuickActionItem, isSignature: Bool) -> some View {
        Button {
            let generator = UISelectionFeedbackGenerator()
            generator.prepare()
            generator.selectionChanged()
            onSetOpen(false)
            item.action()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: item.systemImage)
                    .font(isSignature ? .headline.weight(.semibold) : .subheadline.weight(.semibold))
                    .foregroundStyle(isSignature ? Theme.buttonInk : Theme.accentText)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(isSignature ? Theme.accent : Theme.accent.opacity(0.14)))

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(isSignature ? .headline.weight(.semibold) : .subheadline.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                    if let subtitle = item.subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(Theme.muted)
                    }
                }
                .lineLimit(1)
            }
            .frame(width: 200, alignment: .leading)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilitySortPriority(isSignature ? 2 : 1)
        .accessibilityLabel(item.title)
        .accessibilityHint(item.subtitle ?? "")
    }
}

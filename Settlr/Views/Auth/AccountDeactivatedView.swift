import SwiftUI

/// Shown in place of the whole app once the server reports this account was
/// deactivated. It is a dead end on purpose: there is no retry that can work,
/// so the only way out is signing out.
struct AccountDeactivatedView: View {
    let reason: String?
    let onSignOut: () async -> Void

    @State private var isSigningOut = false

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: 0)

                Image(systemName: "lock.slash")
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(Theme.warning)
                    .frame(width: 76, height: 76)
                    .background(Circle().fill(Theme.warning.opacity(0.12)))

                Text("Account deactivated")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .padding(.top, 24)

                Text("An administrator has turned off access to this account. Your data has not been deleted.")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)
                    .padding(.horizontal, 8)

                if let reason, !reason.isEmpty {
                    reasonCard(reason)
                        .padding(.top, 20)
                }

                Text("Contact support if you think this is a mistake.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.faint)
                    .multilineTextAlignment(.center)
                    .padding(.top, 20)

                Spacer(minLength: 0)

                Button {
                    guard !isSigningOut else { return }
                    isSigningOut = true
                    Task {
                        await onSignOut()
                        isSigningOut = false
                    }
                } label: {
                    Text(isSigningOut ? "Signing out…" : "Sign out")
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(isSigningOut)
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 48)
        }
        .preferredColorScheme(.dark)
    }

    private func reasonCard(_ reason: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("REASON")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .kerning(1)
                .foregroundStyle(Theme.faint)
            Text(reason)
                .font(.system(size: 14))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Theme.surface)
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.line, lineWidth: 1))
        )
    }
}

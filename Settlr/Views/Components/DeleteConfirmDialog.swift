import SwiftUI

struct DeleteConfirmDialog: View {
    let title: String
    let itemName: String
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            Theme.scrim.opacity(0.62)
                .ignoresSafeArea()
                .onTapGesture { onCancel() }

            VStack(spacing: 20) {
                ZStack {
                    Circle()
                        .fill(Theme.expense.opacity(0.12))
                        .frame(width: 56, height: 56)
                    Image(systemName: "trash.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Theme.expense)
                }

                VStack(spacing: 8) {
                    Text(title)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Theme.ink)

                    Text("This action cannot be undone.")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.muted)
                }

                Text(itemName)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Theme.surface2)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .strokeBorder(Theme.line, lineWidth: 1)
                            )
                    )

                HStack(spacing: 12) {
                    Button(action: onCancel) {
                        Text("Cancel")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(Theme.surface2)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14)
                                            .strokeBorder(Theme.line, lineWidth: 1)
                                    )
                            )
                    }
                    .buttonStyle(.plain)

                    Button(action: onConfirm) {
                        Text("Delete")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Theme.destructiveButtonInk)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(Theme.expense)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Theme.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .strokeBorder(Theme.line, lineWidth: 1)
                    )
            )
            .padding(.horizontal, 28)
        }
    }
}

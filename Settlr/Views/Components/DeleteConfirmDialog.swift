import SwiftUI

struct DeleteConfirmDialog: View {
    let title: String
    let itemName: String
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture { onCancel() }

            VStack(spacing: 20) {
                ZStack {
                    Circle()
                        .fill(Color(hex: "#ff6b6b").opacity(0.12))
                        .frame(width: 56, height: 56)
                    Image(systemName: "trash.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Color(hex: "#ff6b6b"))
                }

                VStack(spacing: 8) {
                    Text(title)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Color(hex: "#ecedee"))

                    Text("This action cannot be undone.")
                        .font(.system(size: 14))
                        .foregroundStyle(Color(hex: "#8e9197"))
                }

                Text(itemName)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color(hex: "#ecedee"))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(hex: "#1c1f23"))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .strokeBorder(Color(hex: "#2a2d32"), lineWidth: 1)
                            )
                    )

                HStack(spacing: 12) {
                    Button(action: onCancel) {
                        Text("Cancel")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color(hex: "#ecedee"))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(Color(hex: "#1c1f23"))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14)
                                            .strokeBorder(Color(hex: "#2a2d32"), lineWidth: 1)
                                    )
                            )
                    }
                    .buttonStyle(.plain)

                    Button(action: onConfirm) {
                        Text("Delete")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(Color(hex: "#ff6b6b"))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(hex: "#15171a"))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .strokeBorder(Color(hex: "#2a2d32"), lineWidth: 1)
                    )
            )
            .padding(.horizontal, 28)
        }
    }
}

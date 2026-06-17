import SwiftUI

struct CategoryBadge: View {
    let name: String
    var color: String?

    var body: some View {
        Text(name)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(badgeColor.opacity(0.9))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(badgeColor.opacity(0.15))
            )
    }

    private var badgeColor: Color {
        guard let hex = color, !hex.isEmpty else {
            return Color(hex: "#8e9197")
        }
        return Color(hex: hex)
    }
}

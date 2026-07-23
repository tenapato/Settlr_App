import SwiftUI

struct CategoryBadge: View {
    let name: String
    var color: String?

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(badgeColor)
                .frame(width: 6, height: 6)
            Text(name)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color(hex: "#8e9197"))
                .lineLimit(1)
        }
    }

    private var badgeColor: Color {
        guard let hex = color, !hex.isEmpty else {
            return Color(hex: "#8e9197")
        }
        return Color(hex: hex)
    }
}

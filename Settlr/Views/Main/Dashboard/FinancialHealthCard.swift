import SwiftUI

struct FinancialHealthCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Salud Financiera")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color(hex: "#8e9197"))
                .tracking(1.4)
                .textCase(.uppercase)

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Distribución 50/30/20")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color(hex: "#ecedee"))
                    Spacer()
                    Text("Próximamente")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color(hex: "#c8ff5a"))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule().fill(Color(hex: "#c8ff5a").opacity(0.12))
                        )
                }

                Text("Análisis de tu distribución de gastos según la regla 50/30/20.")
                    .font(.system(size: 13))
                    .foregroundStyle(Color(hex: "#5a5d63"))
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(hex: "#15171a"))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(Color(hex: "#2a2d32"), lineWidth: 1)
                    )
            )
        }
    }
}

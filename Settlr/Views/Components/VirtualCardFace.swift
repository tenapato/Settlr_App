import SwiftUI

enum VirtualCardStyle {
    case compact
    case hero

    var height: CGFloat {
        switch self {
        case .compact: return 118
        case .hero: return 200
        }
    }

    var titleFont: Font {
        switch self {
        case .compact: return .system(size: 17, weight: .semibold)
        case .hero: return .system(size: 22, weight: .semibold)
        }
    }

    var numberFont: Font {
        switch self {
        case .compact: return .system(size: 15, weight: .medium, design: .monospaced)
        case .hero: return .system(size: 20, weight: .medium, design: .monospaced)
        }
    }

    var padding: CGFloat {
        switch self {
        case .compact: return 20
        case .hero: return 24
        }
    }
}

struct VirtualCardFace: View {
    let label: String
    let lastFour: String?
    let network: String?
    let creditLimitCents: Int?
    var style: VirtualCardStyle = .compact

    init(card: CreditCard, style: VirtualCardStyle = .compact) {
        label = card.label
        lastFour = card.lastFour
        network = card.network
        creditLimitCents = card.creditLimitCents
        self.style = style
    }

    private var gradient: LinearGradient {
        let colors: [Color]
        switch network?.lowercased() {
        case "visa":
            colors = [Color(hex: "#0b1a3d"), Color(hex: "#142d6b")]
        case "mastercard":
            colors = [Color(hex: "#160d30"), Color(hex: "#231250")]
        case "amex":
            colors = [Color(hex: "#0a2014"), Color(hex: "#113422")]
        default:
            colors = [Color(hex: "#15171a"), Color(hex: "#1e2228")]
        }
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private var accent: Color {
        switch network?.lowercased() {
        case "visa":       return Color(hex: "#4db8ff")
        case "mastercard": return Color(hex: "#b47ef5")
        case "amex":       return Color(hex: "#5ddf8a")
        default:           return Color(hex: "#c8ff5a")
        }
    }

    private var networkLabel: String {
        switch network?.lowercased() {
        case "visa":       return "VISA"
        case "mastercard": return "MC"
        case "amex":       return "AMEX"
        case "other":      return "OTHER"
        default:           return network?.uppercased() ?? ""
        }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            RadialGradient(
                colors: [accent.opacity(0.12), .clear],
                center: .topLeading,
                startRadius: 0,
                endRadius: style == .hero ? 220 : 160
            )
            .clipShape(RoundedRectangle(cornerRadius: 20))

            VStack(spacing: 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(label.isEmpty ? "Card name" : label)
                            .font(style.titleFont)
                            .foregroundStyle(.white)
                            .lineLimit(2)

                        if let limit = creditLimitCents {
                            HStack(spacing: 3) {
                                Text("Limit")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.35))
                                AmountLabel(cents: limit, font: .system(size: 11, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.45))
                            }
                        }
                    }

                    Spacer()

                    if !networkLabel.isEmpty {
                        Text(networkLabel)
                            .font(.system(size: 10, weight: .bold))
                            .tracking(2.5)
                            .foregroundStyle(accent)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(
                                Capsule()
                                    .fill(accent.opacity(0.12))
                                    .overlay(Capsule().strokeBorder(accent.opacity(0.25), lineWidth: 0.5))
                            )
                    }
                }

                Spacer()

                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(accent.opacity(0.22))
                        .overlay(
                            RoundedRectangle(cornerRadius: 3)
                                .strokeBorder(accent.opacity(0.4), lineWidth: 0.5)
                        )
                        .frame(width: style == .hero ? 34 : 26, height: style == .hero ? 24 : 18)

                    Text(lastFour.map { "•••• •••• •••• \($0)" } ?? "•••• •••• •••• ••••")
                        .font(style.numberFont)
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    Spacer()
                }
            }
            .padding(style.padding)
        }
        .frame(height: style.height)
        .background(gradient)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(.white.opacity(0.07), lineWidth: 1)
        )
    }
}

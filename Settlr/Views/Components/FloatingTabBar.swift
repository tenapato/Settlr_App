import SwiftUI

enum Tab: CaseIterable {
    case home, activity, cards, payments

    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .activity: return "arrow.up.arrow.down"
        case .cards: return "creditcard.fill"
        case .payments: return "calendar"
        }
    }

    var title: String {
        switch self {
        case .home: return "Home"
        case .activity: return "Activity"
        case .cards: return "Cards"
        case .payments: return "Payments"
        }
    }
}

// Pill content — the selected tab expands to show its label; background applied by MainTabView
struct FloatingTabBar: View {
    @Binding var selected: Tab
    /// Only the tabs this user's features leave reachable — an admin can switch
    /// off cards or payments, and a bar item that leads nowhere is worse than
    /// a shorter bar.
    var tabs: [Tab] = Tab.allCases
    @Namespace private var indicatorNS

    var body: some View {
        HStack(spacing: 2) {
            ForEach(tabs, id: \.self) { tab in
                item(for: tab)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func item(for tab: Tab) -> some View {
        let isSelected = selected == tab

        Button {
            withAnimation(.snappy(duration: 0.3)) { selected = tab }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: tab.icon)
                    .font(.system(size: 19, weight: isSelected ? .semibold : .regular))

                if isSelected {
                    Text(tab.title)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .fixedSize()
                        .transition(.opacity)
                }
            }
            .foregroundStyle(isSelected ? Color(hex: "#c8ff5a") : Color(hex: "#8e9197"))
            .padding(.horizontal, isSelected ? 14 : 0)
            .padding(.vertical, 13)
            // Selected item claims its intrinsic width so the label can't clip;
            // the remaining space is split evenly by the other three.
            .frame(maxWidth: isSelected ? nil : CGFloat.infinity)
            .fixedSize(horizontal: isSelected, vertical: false)
            .contentShape(Rectangle())
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(hex: "#c8ff5a").opacity(0.14))
                        .matchedGeometryEffect(id: "indicator", in: indicatorNS)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: .init(charactersIn: "#"))
        let scanner = Scanner(string: hex)
        var rgb: UInt64 = 0
        scanner.scanHexInt64(&rgb)
        let r = Double((rgb >> 16) & 0xFF) / 255
        let g = Double((rgb >> 8) & 0xFF) / 255
        let b = Double(rgb & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

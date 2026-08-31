import SwiftUI

enum Tab: CaseIterable {
    case home, activity, savings, cards

    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .activity: return "arrow.up.arrow.down"
        case .savings: return "banknote"
        case .cards: return "creditcard.fill"
        }
    }

    var title: String {
        switch self {
        case .home: return "Home"
        case .activity: return "Activity"
        case .savings: return "Savings"
        case .cards: return "Cards"
        }
    }
}

/// Compact peer navigation. Every tab keeps its label visible so selection
/// never changes the bar's geometry or makes destinations ambiguous.
struct FloatingTabBar: View {
    @Binding var selected: Tab
    /// Only the tabs this user's features leave reachable — an admin can switch
    /// off cards or savings, and a bar item that leads nowhere is worse than
    /// a shorter bar.
    var tabs: [Tab] = Tab.allCases
    var body: some View {
        HStack(spacing: 2) {
            ForEach(tabs, id: \.self) { tab in
                item(for: tab)
            }
        }
        .padding(4)
    }

    @ViewBuilder
    private func item(for tab: Tab) -> some View {
        let isSelected = selected == tab

        Button {
            selected = tab
        } label: {
            VStack(spacing: 3) {
                Image(systemName: tab.icon)
                    .font(.system(size: 15, weight: isSelected ? .semibold : .regular))

                Text(tab.title)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .allowsTightening(true)
            }
            .foregroundStyle(isSelected ? Theme.accentText : Theme.muted)
            .frame(maxWidth: .infinity, minHeight: 49)
            .contentShape(Rectangle())
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

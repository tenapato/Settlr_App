import SwiftUI

enum Tab: CaseIterable {
    case home, cards, expenses, income, categories

    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .cards: return "creditcard.fill"
        case .expenses: return "arrow.down.circle.fill"
        case .income: return "arrow.up.circle.fill"
        case .categories: return "tag.fill"
        }
    }
}

// Pill content — 5 tabs icon-only; background applied by MainTabView
struct FloatingTabBar: View {
    @Binding var selected: Tab
    @Namespace private var indicatorNS

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.snappy(duration: 0.3)) { selected = tab }
                } label: {
                    Image(systemName: tab.icon)
                        .font(.system(size: 19, weight: selected == tab ? .semibold : .regular))
                        .foregroundStyle(
                            selected == tab ? Color(hex: "#c8ff5a") : Color(hex: "#8e9197")
                        )
                        .animation(.snappy(duration: 0.2), value: selected)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .contentShape(Rectangle())
                        .background {
                            if selected == tab {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color(hex: "#c8ff5a").opacity(0.14))
                                    .matchedGeometryEffect(id: "indicator", in: indicatorNS)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
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

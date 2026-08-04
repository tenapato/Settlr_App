import SwiftUI

enum CardsCategoriesSegment: String, CaseIterable {
    case cards
    case categories

    var title: String {
        switch self {
        case .cards: return "Cards"
        case .categories: return "Categories"
        }
    }
}

struct CardsAndCategoriesView: View {
    let workspaceId: String
    @Binding var selectedSegment: CardsCategoriesSegment

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: $selectedSegment) {
                    ForEach(CardsCategoriesSegment.allCases, id: \.self) { segment in
                        Text(segment.title).tag(segment)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 24)
                .padding(.bottom, 8)

                Group {
                    switch selectedSegment {
                    case .cards:
                        CardsView(workspaceId: workspaceId, embedded: true)
                    case .categories:
                        CategoriesView(workspaceId: workspaceId, embedded: true)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle(selectedSegment.title)
            .navigationBarTitleDisplayMode(.large)
        }
        .preferredColorScheme(.dark)
    }
}

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
    @Environment(AppState.self) private var appState

    private var segments: [CardsCategoriesSegment] {
        CardsCategoriesSegment.available(for: appState.currentUser)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // With only Cards or only Categories left there is nothing to
                // switch between, so the control is dropped rather than shown
                // as a single dead segment.
                if segments.count > 1 {
                    Picker("", selection: $selectedSegment) {
                        ForEach(segments, id: \.self) { segment in
                            Text(segment.title).tag(segment)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 8)
                }

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
        .onAppear(perform: reconcileSegment)
        .onChange(of: segments) { _, _ in reconcileSegment() }
    }

    /// The segment is owned by `MainTabView` so it survives navigation, and can
    /// therefore outlive the feature that justified it.
    private func reconcileSegment() {
        guard let first = segments.first, !segments.contains(selectedSegment) else { return }
        selectedSegment = first
    }
}

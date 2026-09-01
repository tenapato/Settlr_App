import SwiftUI

enum SplitItemFilter: CaseIterable, Hashable {
    case needsReview
    case all

    var title: String {
        switch self {
        case .needsReview: "Needs review"
        case .all: "All items"
        }
    }
}

struct SplitItemsPresentation {
    private let filledItems: [SplitDraft.Item]

    let itemCount: Int
    let participantCount: Int
    let reviewCount: Int
    let subtotalCents: Int

    init(draft: SplitDraft) {
        filledItems = draft.filledItems
        itemCount = filledItems.count
        participantCount = draft.participants.count
        reviewCount = filledItems.filter { $0.verification == .unverified }.count
        subtotalCents = filledItems.reduce(0) { $0 + $1.lineTotalCents }
    }

    var availableFilters: [SplitItemFilter] {
        reviewCount > 0 ? SplitItemFilter.allCases : [.all]
    }

    func normalizedFilter(_ filter: SplitItemFilter) -> SplitItemFilter {
        availableFilters.contains(filter) ? filter : .all
    }

    func items(for filter: SplitItemFilter) -> [SplitDraft.Item] {
        switch normalizedFilter(filter) {
        case .needsReview:
            filledItems.filter { $0.verification == .unverified }
        case .all:
            filledItems
        }
    }
}

struct SplitItemsStepView: View {
    @Binding var draft: SplitDraft
    @Binding var filter: SplitItemFilter
    let validationIssue: GuidedSplitValidationIssue?
    let onEditItem: (SplitDraft.Item) -> Void
    let onAddItem: () -> Void
    let onContinue: () -> Void

    private var presentation: SplitItemsPresentation { .init(draft: draft) }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                SectionEyebrow("Split by item")
                Text("Review items")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Theme.ink)
                Text("\(presentation.itemCount) items · \(presentation.participantCount) people · \(formatSplitMoney(presentation.subtotalCents))")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.muted)
            }

            if presentation.availableFilters.count > 1 {
                HStack(spacing: 8) {
                    ForEach(presentation.availableFilters, id: \.self) { option in
                        filterButton(option)
                    }
                }
            }

            FormCard {
                ForEach(presentation.items(for: filter)) { item in
                    Button { onEditItem(item) } label: {
                        itemRow(item)
                    }
                    .buttonStyle(.plain)
                    if item.id != presentation.items(for: filter).last?.id {
                        FormRowDivider()
                    }
                }
            }

            Button(action: onAddItem) {
                Label("Add item", systemImage: "plus")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.accentText)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Theme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Theme.line, lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)

            if let validationIssue, validationIssue.step == .items {
                Text(validationIssue.message)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.warning)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            SplitStickyAction(title: "Continue", action: onContinue)
        }
        .onAppear(perform: normalizeFilter)
        .onChange(of: presentation.reviewCount) { _, _ in normalizeFilter() }
    }

    private func filterButton(_ option: SplitItemFilter) -> some View {
        Button { filter = option } label: {
            Text(option.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(filter == option ? Theme.buttonInk : Theme.muted)
                .padding(.horizontal, 12)
                .frame(minHeight: 34)
                .background(filter == option ? Theme.accent : Theme.surface2)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityValue(filter == option ? "Selected" : "Not selected")
    }

    private func itemRow(_ item: SplitDraft.Item) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(item.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Unnamed item" : item.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 7) {
                    if item.quantity > 1 {
                        Text("Qty \(item.quantity)")
                    }
                    Text(allocationLabel(item.allocationMode))
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.muted)
                if item.verification == .unverified {
                    Label("Needs review", systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.warning)
                }
            }
            Text(formatSplitMoney(item.lineTotalCents))
                .font(.system(size: 15, weight: .bold, design: .monospaced))
                .foregroundStyle(Theme.ink)
        }
        .padding(16)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func allocationLabel(_ allocationMode: String) -> String {
        allocationMode == "units" ? "By units" : "Shared"
    }

    private func normalizeFilter() {
        filter = presentation.normalizedFilter(filter)
    }
}

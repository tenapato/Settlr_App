import SwiftUI

struct SplitReceiptHeaderPresentation: Equatable {
    let merchant: String
    let date: Date
    let paymentLabel: String
    let totalCents: Int
    let warningCount: Int

    init(draft: SplitDraft, totalCents: Int) {
        merchant = draft.merchant.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Receipt" : draft.merchant
        date = draft.occurredAt
        paymentLabel = draft.paymentChannel == "credit_card" ? "Credit card" : "Cash / debit"
        self.totalCents = totalCents
        warningCount = draft.scanWarnings.count + draft.unverifiedItems.count
    }
}

extension GuidedSplitFlowPolicy {
    static func setupActionTitle(splitMode: String, itemCount: Int) -> String {
        guard splitMode == "by_item" else { return "Check total" }
        return "Review \(max(0, itemCount)) items"
    }
}

struct SplitReceiptHeader: View {
    let presentation: SplitReceiptHeaderPresentation
    let onEditReceipt: () -> Void
    let onScanAgain: () -> Void
    let onOpenParserSettings: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(presentation.merchant)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(2)
                Text(presentation.date, format: .dateTime.year().month(.abbreviated).day())
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.muted)
                Text(presentation.paymentLabel)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 8) {
                Menu {
                    Button("Edit receipt details", action: onEditReceipt)
                    Button("Scan again", action: onScanAgain)
                    Button("Receipt parsing settings", action: onOpenParserSettings)
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Theme.muted)
                        .frame(width: 44, height: 30, alignment: .trailing)
                }
                Text(formatSplitMoney(presentation.totalCents))
                    .font(.system(size: 20, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.ink)
                if presentation.warningCount > 0 {
                    Label("\(presentation.warningCount)", systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.warning)
                        .accessibilityLabel("\(presentation.warningCount) receipt warnings")
                }
            }
        }
        .padding(16)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Theme.line, lineWidth: 1)
        }
    }
}

struct SplitProgressRail: View {
    let step: GuidedSplitStep

    private let steps: [(GuidedSplitStep, String)] = [(.setup, "Setup"), (.items, "Items"), (.confirm, "Confirm")]

    private var index: Int { steps.firstIndex { $0.0 == step } ?? 0 }

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(steps.enumerated()), id: \.offset) { offset, item in
                HStack(spacing: 6) {
                    Text("\(offset + 1)")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(offset <= index ? Theme.buttonInk : Theme.muted)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(offset <= index ? Theme.accent : Theme.surface2))
                    Text(item.1)
                        .font(.system(size: 12, weight: offset == index ? .semibold : .medium))
                        .foregroundStyle(offset == index ? Theme.ink : Theme.muted)
                }
                if offset < steps.count - 1 {
                    Rectangle().fill(offset < index ? Theme.accent : Theme.line).frame(height: 1)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(index + 1) of 3")
        .accessibilityValue(steps[index].1)
    }
}

struct SplitStickyAction: View {
    let title: String
    var isSubmitting = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if isSubmitting {
                    ProgressView().tint(Theme.buttonInk)
                } else {
                    Text(title)
                }
            }
        }
        .buttonStyle(PrimaryButtonStyle())
        .disabled(isSubmitting)
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(Theme.bg)
        .ignoresSafeArea(edges: .bottom)
        .accessibilityLabel(isSubmitting ? "Submitting split" : title)
    }
}

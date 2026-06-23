import SwiftUI

enum LedgerTagTone {
    case neutral
    case success
    case warning
    case accent
}

struct LedgerTag: View {
    let text: String
    var tone: LedgerTagTone = .neutral
    var compact: Bool = false

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: compact ? 10 : 11, weight: .semibold, design: .monospaced))
            .tracking(compact ? 0 : 0.6)
            .foregroundStyle(foreground)
            .padding(.horizontal, compact ? 5 : 6)
            .padding(.vertical, compact ? 3 : 4)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(background)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(border, lineWidth: tone == .neutral ? 1 : 0)
                    )
            )
            .fixedSize()
    }

    private var foreground: Color {
        switch tone {
        case .neutral: return Color(hex: "#8e9197")
        case .success: return Color(hex: "#5ddf8a")
        case .warning: return Color(hex: "#ffb547")
        case .accent: return Color(hex: "#c8ff5a")
        }
    }

    private var background: Color {
        foreground.opacity(tone == .neutral ? 0.08 : 0.14)
    }

    private var border: Color {
        tone == .neutral ? Color(hex: "#2a2d32") : .clear
    }
}

enum LedgerMarkers {
    static let statementVerifiedPrefix = "Verified · statement:"

    static func msiTagLabel(installment: Int?, count: Int?) -> String? {
        guard let meta = installmentMetadata(installment: installment, count: count) else { return nil }
        return "MSI \(meta.installment)/\(meta.count)"
    }

    static func deferredTagLabel(installment: Int?, count: Int?) -> String? {
        guard let meta = installmentMetadata(installment: installment, count: count) else { return nil }
        return "DIF \(meta.installment)/\(meta.count)"
    }

    static func isStatementVerified(notes: String?) -> Bool {
        guard let notes else { return false }
        return notes.contains(statementVerifiedPrefix)
    }

    static func channelTagLabel(for paymentChannel: String) -> String? {
        switch paymentChannel {
        case "cash": return "cash"
        case "credit_card": return "card"
        default: return nil
        }
    }

    private static func installmentMetadata(installment: Int?, count: Int?) -> (installment: Int, count: Int)? {
        guard let installment, let count, installment >= 1, count >= 2, installment <= count else { return nil }
        return (installment, count)
    }
}

struct ExpenseMarkerTags: View {
    let expense: Expense

    var body: some View {
        HStack(spacing: 6) {
            if let label = expense.msiTagLabel {
                LedgerTag(text: label, tone: .accent)
            }
            if let label = expense.deferredTagLabel {
                LedgerTag(text: label, tone: .warning)
            }
            if expense.isStatementVerified {
                LedgerTag(text: "V", tone: .success, compact: true)
            }
        }
    }
}

struct IncomeMarkerTags: View {
    let income: Income

    var body: some View {
        Group {
            if income.isRecurring {
                LedgerTag(text: "monthly", tone: .neutral)
            }
        }
    }
}

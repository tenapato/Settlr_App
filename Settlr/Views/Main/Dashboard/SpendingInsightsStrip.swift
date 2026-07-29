import SwiftUI
import Foundation

// MARK: - Insight model

struct SpendingInsight: Identifiable {
    enum Tone {
        case neutral, good, bad

        var color: Color {
            switch self {
            case .neutral: return Theme.accent
            case .good:    return Theme.income
            case .bad:     return Theme.expense
            }
        }
    }

    let id: String
    let eyebrow: String     // "MAYOR GASTO"
    let title: String       // "Comida"
    let value: String       // "▲ +142%"
    let detail: String?     // "MXN $4,820.00"
    let tone: Tone
    let swatch: Color?      // category dot, nil for non-category tiles
}

// MARK: - Insight engine

enum SpendingInsights {
    private static let noiseFloorCents = 5_000
    private static let noiseFloorFraction = 0.02

    static func build(current: SummaryResponse, previous: SummaryResponse?, months: [MonthDataPoint]) -> [SpendingInsight] {
        let categories = current.sortedCategories
        guard current.expenseCents > 0, !categories.isEmpty else { return [] }

        let totalCents = current.expenseCents
        var tiles: [SpendingInsight] = []

        // Pinned: top category, always first.
        if let top = categories.first {
            let fraction = Double(top.totalCents) / Double(totalCents)
            tiles.append(SpendingInsight(
                id: "top-category",
                eyebrow: "MAYOR GASTO",
                title: top.categoryName ?? "Sin categoría",
                value: percentString(fraction),
                detail: currencyString(top.totalCents),
                tone: .neutral,
                swatch: swatchColor(at: 0)
            ))
        }

        var candidates: [(insight: SpendingInsight, score: Double)] = []

        // --- Candidates that require the previous month's category totals ---
        if let previous {
            let previousById = Dictionary(uniqueKeysWithValues: previous.expensesByCategory.map { ($0.id, $0) })

            struct Delta {
                let category: CategorySummary
                let swatch: Color
                let previousCents: Int
                let deltaCents: Int
            }

            var deltas: [Delta] = []
            var newSpending: [(category: CategorySummary, swatch: Color)] = []

            for (i, cat) in categories.enumerated() {
                let prevCents = previousById[cat.id]?.totalCents ?? 0
                let swatch = swatchColor(at: i)
                if prevCents == 0 {
                    let passesFloor = cat.totalCents >= noiseFloorCents
                        && Double(cat.totalCents) >= noiseFloorFraction * Double(totalCents)
                    if passesFloor {
                        newSpending.append((cat, swatch))
                    }
                } else {
                    let deltaCents = cat.totalCents - prevCents
                    let passesFloor = abs(deltaCents) >= noiseFloorCents
                        && Double(abs(deltaCents)) >= noiseFloorFraction * Double(totalCents)
                    if passesFloor {
                        deltas.append(Delta(category: cat, swatch: swatch, previousCents: prevCents, deltaCents: deltaCents))
                    }
                }
            }

            // Biggest increase.
            if let inc = deltas.filter({ $0.deltaCents > 0 }).max(by: { $0.deltaCents < $1.deltaCents }) {
                let fraction = Double(inc.deltaCents) / Double(inc.previousCents)
                let score = Double(inc.deltaCents) / Double(totalCents)
                candidates.append((SpendingInsight(
                    id: "biggest-increase",
                    eyebrow: "MAYOR ALZA",
                    title: inc.category.categoryName ?? "Sin categoría",
                    value: signedPercentString(fraction),
                    detail: currencyString(inc.category.totalCents),
                    tone: .bad,
                    swatch: inc.swatch
                ), score))
            }

            // Biggest decrease.
            if let dec = deltas.filter({ $0.deltaCents < 0 }).min(by: { $0.deltaCents < $1.deltaCents }) {
                let fraction = Double(dec.deltaCents) / Double(dec.previousCents)
                let score = Double(abs(dec.deltaCents)) / Double(totalCents)
                candidates.append((SpendingInsight(
                    id: "biggest-decrease",
                    eyebrow: "MAYOR BAJA",
                    title: dec.category.categoryName ?? "Sin categoría",
                    value: signedPercentString(fraction),
                    detail: currencyString(dec.category.totalCents),
                    tone: .good,
                    swatch: dec.swatch
                ), score))
            }

            // New spending.
            if let new = newSpending.max(by: { $0.category.totalCents < $1.category.totalCents }) {
                let score = Double(new.category.totalCents) / Double(totalCents)
                candidates.append((SpendingInsight(
                    id: "new-spending",
                    eyebrow: "GASTO NUEVO",
                    title: new.category.categoryName ?? "Sin categoría",
                    value: currencyString(new.category.totalCents),
                    detail: "Nueva este mes",
                    tone: .bad,
                    swatch: new.swatch
                ), score))
            }

            // Total vs last month.
            let prevTotal = previous.expenseCents
            if prevTotal > 0 {
                let fraction = Double(totalCents - prevTotal) / Double(prevTotal)
                if abs(fraction) >= 0.02 {
                    candidates.append((SpendingInsight(
                        id: "vs-last-month",
                        eyebrow: "VS MES ANTERIOR",
                        title: fraction > 0 ? "Subiste" : "Bajaste",
                        value: signedPercentString(fraction),
                        detail: currencyString(totalCents),
                        tone: fraction > 0 ? .bad : .good,
                        swatch: nil
                    ), abs(fraction)))
                }
            }
        }

        // Concentration.
        if categories.count >= 3 {
            let top3Cents = categories.prefix(3).reduce(0) { $0 + $1.totalCents }
            let share = Double(top3Cents) / Double(totalCents)
            if share >= 0.5 {
                candidates.append((SpendingInsight(
                    id: "concentration",
                    eyebrow: "CONCENTRACIÓN",
                    title: "Top 3 categorías",
                    value: percentString(share),
                    detail: "del total del mes",
                    tone: .neutral,
                    swatch: nil
                ), share - 0.5))
            }
        }

        // Card vs cash.
        let channel = current.expensesByChannel
        if channel.cashCents > 0 && channel.creditCardCents > 0 {
            let channelTotal = channel.cashCents + channel.creditCardCents
            let cardShare = Double(channel.creditCardCents) / Double(channelTotal)
            let dominantShare = max(cardShare, 1 - cardShare)
            candidates.append((SpendingInsight(
                id: "card-vs-cash",
                eyebrow: "TARJETA VS EFECTIVO",
                title: cardShare >= 0.5 ? "Tarjeta" : "Efectivo",
                value: percentString(dominantShare),
                detail: "del gasto total",
                tone: .neutral,
                swatch: nil
            ), abs(cardShare - 0.5) * 2))
        }

        // Savings rate.
        if current.incomeCents > 0 && current.netCents > 0 {
            let rate = Double(current.netCents) / Double(current.incomeCents)
            candidates.append((SpendingInsight(
                id: "savings-rate",
                eyebrow: "TASA DE AHORRO",
                title: "Ahorraste",
                value: percentString(rate),
                detail: currencyString(current.netCents),
                tone: .good,
                swatch: nil
            ), rate))
        }

        // Vs annual average.
        let monthsWithExpense = months.filter { $0.expenseCents > 0 }
        if monthsWithExpense.count >= 2 {
            let avg = Double(monthsWithExpense.reduce(0) { $0 + $1.expenseCents }) / Double(monthsWithExpense.count)
            if avg > 0 {
                let fraction = (Double(totalCents) - avg) / avg
                if abs(fraction) >= 0.05 {
                    candidates.append((SpendingInsight(
                        id: "vs-average",
                        eyebrow: "VS PROMEDIO",
                        title: fraction > 0 ? "Más que tu promedio" : "Menos que tu promedio",
                        value: signedPercentString(fraction),
                        detail: "Prom: " + currencyString(Int(avg)),
                        tone: fraction > 0 ? .bad : .good,
                        swatch: nil
                    ), abs(fraction)))
                }
            }
        }

        let ranked = candidates.sorted { $0.score > $1.score }.prefix(4).map(\.insight)
        tiles.append(contentsOf: ranked)
        return tiles
    }

    private static func swatchColor(at index: Int) -> Color {
        index < 5 ? Theme.categoryPalette[index % Theme.categoryPalette.count] : Theme.categoryOther
    }

    private static func percentString(_ fraction: Double) -> String {
        String(format: "%.0f%%", fraction * 100)
    }

    private static func signedPercentString(_ fraction: Double) -> String {
        let pct = fraction * 100
        let arrow = pct >= 0 ? "▲" : "▼"
        let sign = pct >= 0 ? "+" : "-"
        let magnitude = abs(pct)
        let formatted = magnitude < 10 ? String(format: "%.1f", magnitude) : String(format: "%.0f", magnitude)
        return "\(arrow) \(sign)\(formatted)%"
    }

    private static func currencyString(_ cents: Int) -> String {
        let value = Double(cents) / 100.0
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.groupingSeparator = ","
        formatter.decimalSeparator = "."
        let number = formatter.string(from: NSNumber(value: value)) ?? "\(value)"
        return "MXN $\(number)"
    }
}

// MARK: - Composition bar

struct SpendingCompositionBar: View {
    let summary: SummaryResponse
    var appeared: Bool = true

    private struct Segment: Identifiable {
        let id: String
        let name: String
        let cents: Int
        let fraction: Double
        let color: Color
    }

    private var segments: [Segment] {
        let categories = summary.sortedCategories
        let total = summary.expenseCents
        guard total > 0, !categories.isEmpty else { return [] }

        let top5 = Array(categories.prefix(5))
        var result: [Segment] = top5.enumerated().map { i, cat in
            Segment(
                id: cat.id,
                name: cat.categoryName ?? "Sin categoría",
                cents: cat.totalCents,
                fraction: Double(cat.totalCents) / Double(total),
                color: Theme.categoryPalette[i % Theme.categoryPalette.count]
            )
        }

        let shownCents = top5.reduce(0) { $0 + $1.totalCents }
        let otherCents = total - shownCents
        if otherCents > 0 {
            result.append(Segment(
                id: "other",
                name: "Otros",
                cents: otherCents,
                fraction: Double(otherCents) / Double(total),
                color: Theme.categoryOther
            ))
        }
        return result
    }

    private var legendEntries: [Segment] {
        let real = segments.filter { $0.id != "other" }
        let count = real.count <= 3 ? real.count : 2
        return Array(real.prefix(count))
    }

    private var remainingCount: Int {
        summary.sortedCategories.count - legendEntries.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geo in
                let widths = computedWidths(availableWidth: geo.size.width)
                HStack(spacing: 2) {
                    ForEach(Array(segments.enumerated()), id: \.element.id) { i, seg in
                        Rectangle()
                            .fill(seg.color)
                            .frame(width: appeared ? widths[i] : 0)
                    }
                }
            }
            .frame(height: 8)
            .clipShape(Capsule())

            legend
        }
    }

    private var legend: some View {
        HStack(spacing: 14) {
            ForEach(legendEntries) { seg in
                HStack(spacing: 5) {
                    Circle().fill(seg.color).frame(width: 5, height: 5)
                    Text(seg.name)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text("\(Int((seg.fraction * 100).rounded()))%")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .monospacedDigit()
                }
            }
            if remainingCount > 0 {
                Text("+\(remainingCount) más")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.faint)
            }
            Spacer(minLength: 0)
        }
    }

    private func computedWidths(availableWidth: CGFloat) -> [CGFloat] {
        let spacing: CGFloat = 2
        let minWidth: CGFloat = 3
        let segs = segments
        guard !segs.isEmpty else { return [] }
        let usable = max(0, availableWidth - spacing * CGFloat(segs.count - 1))
        var widths = segs.map { usable * CGFloat($0.fraction) }

        let smallIdx = widths.indices.filter { widths[$0] < minWidth }
        if !smallIdx.isEmpty {
            let deficit = smallIdx.reduce(CGFloat(0)) { $0 + (minWidth - widths[$1]) }
            for i in smallIdx { widths[i] = minWidth }
            let bigIdx = widths.indices.filter { !smallIdx.contains($0) }
            let bigTotal = bigIdx.reduce(CGFloat(0)) { $0 + widths[$1] }
            if bigTotal > deficit {
                for i in bigIdx {
                    let share = widths[i] / bigTotal
                    widths[i] -= deficit * share
                }
            }
        }
        return widths
    }
}

// MARK: - Insight Ticker building blocks

private struct TickerWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct TickerDot: View {
    var body: some View {
        Text("·")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Theme.faint)
    }
}

private struct TickerLineView: View {
    let insight: SpendingInsight

    var body: some View {
        HStack(spacing: 6) {
            if let swatch = insight.swatch {
                Circle().fill(swatch).frame(width: 6, height: 6)
            }
            Text(insight.title)
                .foregroundStyle(Theme.ink)
            Text(insight.value)
                .foregroundStyle(insight.tone.color)
                .monospacedDigit()
        }
        .font(.system(size: 13, weight: .semibold, design: .rounded))
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
    }
}

// MARK: - Insight Ticker

struct InsightTicker: View {
    let insights: [SpendingInsight]
    var onTap: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var contentWidth: CGFloat = 0
    @State private var baseOffset: CGFloat = 0
    @State private var baseTime: Date?
    @State private var isDragging = false
    @State private var dragTranslation: CGFloat = 0
    @State private var resumeTask: DispatchWorkItem?

    private let speed: CGFloat = 30
    private let itemSpacing: CGFloat = 16
    private let repeatCount = 8

    var body: some View {
        Group {
            if reduceMotion {
                staticRow
            } else {
                animatedRow
            }
        }
    }

    private var oneCycle: some View {
        HStack(spacing: itemSpacing) {
            ForEach(insights) { insight in
                TickerLineView(insight: insight)
                TickerDot()
            }
        }
    }

    private var staticRow: some View {
        ScrollView(.horizontal) {
            HStack(spacing: itemSpacing) {
                ForEach(Array(insights.enumerated()), id: \.element.id) { i, insight in
                    Button(action: onTap) {
                        TickerLineView(insight: insight)
                    }
                    .buttonStyle(.plain)
                    if i < insights.count - 1 { TickerDot() }
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private var animatedRow: some View {
        TimelineView(.animation) { timeline in
            HStack(spacing: itemSpacing) {
                ForEach(0..<repeatCount, id: \.self) { _ in oneCycle }
            }
            .offset(x: contentWidth > 0 ? currentOffset(at: timeline.date) : 0)
        }
        .frame(height: 20)
        .clipped()
        .background(
            oneCycle
                .opacity(0)
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(key: TickerWidthKey.self, value: geo.size.width)
                    }
                )
        )
        .onPreferenceChange(TickerWidthKey.self) { contentWidth = $0 + itemSpacing }
        .contentShape(Rectangle())
        .gesture(dragGesture)
        .onAppear {
            baseOffset = 0
            baseTime = Date()
        }
        .onChange(of: insights.map(\.id)) { _, _ in
            resumeTask?.cancel()
            isDragging = false
            dragTranslation = 0
            baseOffset = 0
            baseTime = Date()
        }
    }

    private func currentOffset(at date: Date) -> CGFloat {
        guard contentWidth > 0 else { return 0 }
        let raw: CGFloat
        if isDragging {
            raw = baseOffset + dragTranslation
        } else if let baseTime {
            raw = baseOffset - CGFloat(date.timeIntervalSince(baseTime)) * speed
        } else {
            raw = baseOffset
        }
        var wrapped = raw.truncatingRemainder(dividingBy: contentWidth)
        if wrapped > 0 { wrapped -= contentWidth }
        return wrapped
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if !isDragging {
                    let frozen = currentOffset(at: Date())
                    resumeTask?.cancel()
                    baseOffset = frozen
                    baseTime = nil
                    isDragging = true
                }
                dragTranslation = value.translation.width
            }
            .onEnded { value in
                baseOffset += value.translation.width
                dragTranslation = 0
                isDragging = false
                scheduleResume()
                if abs(value.translation.width) < 5 && abs(value.translation.height) < 5 {
                    onTap()
                }
            }
    }

    private func scheduleResume() {
        let task = DispatchWorkItem { baseTime = Date() }
        resumeTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: task)
    }
}

// Note: `oneCycle` puts a `TickerDot()` after every insight, including the last one in the sequence — this is deliberate. When `repeatCount` copies of `oneCycle` sit back-to-back in the outer `HStack`, that trailing dot becomes the separator between the last item of one copy and the first item of the next, so the loop seam gets a dot too, indistinguishable from every other gap.

// MARK: - Insight tile

struct InsightTile: View {
    let insight: SpendingInsight
    var onTap: () -> Void = {}

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 6) {
                Text(insight.eyebrow)
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(1.0)
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)

                HStack(spacing: 5) {
                    if let swatch = insight.swatch {
                        Circle().fill(swatch).frame(width: 6, height: 6)
                    }
                    Text(insight.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Text(insight.value)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(insight.tone.color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                if let detail = insight.detail {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.faint)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(width: 148, height: 84, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Theme.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(Theme.line, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Assembled strip

struct SpendingInsightsStrip: View {
    let summary: SummaryResponse
    let previous: SummaryResponse?
    let months: [MonthDataPoint]
    var onTap: () -> Void = {}

    @State private var appeared = false

    private var insights: [SpendingInsight] {
        SpendingInsights.build(current: summary, previous: previous, months: months)
    }

    var body: some View {
        if summary.expenseCents == 0 || summary.sortedCategories.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 14) {
                header
                    .padding(.horizontal, 24)

                SpendingCompositionBar(summary: summary, appeared: appeared)
                    .padding(.horizontal, 24)

                tilesRow
            }
            .onAppear { reveal() }
            .onChange(of: summary.expenseCents) { _, _ in
                appeared = false
                reveal()
            }
        }
    }

    private func reveal() {
        withAnimation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.15)) {
            appeared = true
        }
    }

    private var header: some View {
        HStack {
            SectionEyebrow("GASTOS DEL MES")
            Spacer()
            AmountLabel(cents: summary.expenseCents, font: .system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.muted)
        }
    }

    private var tilesRow: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 10) {
                ForEach(Array(insights.enumerated()), id: \.element.id) { i, insight in
                    InsightTile(insight: insight, onTap: onTap)
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 12)
                        .animation(
                            .spring(response: 0.6, dampingFraction: 0.8).delay(0.15 + Double(i) * 0.07),
                            value: appeared
                        )
                }
            }
        }
        .scrollIndicators(.hidden)
        .contentMargins(.horizontal, 24, for: .scrollContent)
    }
}

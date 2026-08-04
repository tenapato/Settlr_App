import SwiftUI

struct AnnualEvolutionChart: View {
    let months: [MonthDataPoint]
    var isLoading: Bool = false

    private let monthLabels = ["Ene","Feb","Mar","Abr","May","Jun","Jul","Ago","Sep","Oct","Nov","Dic"]
    private let incomeColor  = Color(hex: "#5ddf8a")
    private let expenseColor = Color(hex: "#ff6b6b")
    private let balanceColor = Color(hex: "#7b9cff")
    private let savingsColor = Color(hex: "#c8ff5a")

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Evolución Anual")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color(hex: "#8e9197"))
                .tracking(1.4)
                .textCase(.uppercase)

            VStack(alignment: .leading, spacing: 10) {
                legendRow
                chartCanvas
                    .frame(height: 160)
                monthAxisRow
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(hex: "#15171a"))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(Color(hex: "#2a2d32"), lineWidth: 1)
                    )
            )
        }
        .redacted(reason: isLoading ? .placeholder : [])
    }

    private var legendRow: some View {
        HStack(spacing: 14) {
            legendDot(color: incomeColor,  label: "Ingresos")
            legendDot(color: expenseColor, label: "Gastos")
            legendDot(color: balanceColor, label: "Balance")
            legendDot(color: savingsColor, label: "Ahorros")
            Spacer()
        }
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color(hex: "#8e9197"))
        }
    }

    private var chartCanvas: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let data = paddedMonths

            let maxVal = max(
                data.map(\.incomeCents).max() ?? 0,
                data.map(\.expenseCents).max() ?? 0,
                data.map { max(0, $0.savingsNetCents) }.max() ?? 0,
                1
            )

            Canvas { ctx, _ in
                drawGrid(ctx: ctx, w: w, h: h, maxVal: maxVal)
                drawAreaFill(ctx: ctx, w: w, h: h, maxVal: maxVal, data: data,
                             keyPath: \.incomeCents, color: incomeColor)
                drawAreaFill(ctx: ctx, w: w, h: h, maxVal: maxVal, data: data,
                             keyPath: \.expenseCents, color: expenseColor)
                drawLine(ctx: ctx, w: w, h: h, maxVal: maxVal, data: data,
                         keyPath: \.incomeCents, color: incomeColor, width: 2)
                drawLine(ctx: ctx, w: w, h: h, maxVal: maxVal, data: data,
                         keyPath: \.expenseCents, color: expenseColor, width: 2)
                drawLine(ctx: ctx, w: w, h: h, maxVal: maxVal, data: data,
                         keyPath: \.netCents, color: balanceColor, width: 1.5, dash: [5, 4])
                drawLine(ctx: ctx, w: w, h: h, maxVal: maxVal, data: data,
                         keyPath: \.savingsNetCents, color: savingsColor, width: 1.5, dash: [2, 3])
            }
        }
    }

    private var monthAxisRow: some View {
        HStack(spacing: 0) {
            ForEach(Array(monthLabels.enumerated()), id: \.offset) { _, label in
                Text(label)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Color(hex: "#5a5d63"))
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var paddedMonths: [MonthDataPoint] {
        guard months.count == 12 else { return months }
        return months
    }

    private func xPos(index: Int, count: Int, w: CGFloat) -> CGFloat {
        guard count > 1 else { return w / 2 }
        return CGFloat(index) / CGFloat(count - 1) * w
    }

    private func yPos(value: Int, maxVal: Int, h: CGFloat) -> CGFloat {
        let ratio = maxVal > 0 ? Double(max(0, value)) / Double(maxVal) : 0
        return h - CGFloat(ratio) * h * 0.9
    }

    private func drawGrid(ctx: GraphicsContext, w: CGFloat, h: CGFloat, maxVal: Int) {
        for step in [0.25, 0.5, 0.75, 1.0] {
            let y = h - CGFloat(step) * h * 0.9
            var path = Path()
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: w, y: y))
            ctx.stroke(path, with: .color(Color(hex: "#2a2d32").opacity(0.6)), lineWidth: 1)
        }
    }

    private func points(data: [MonthDataPoint], keyPath: KeyPath<MonthDataPoint, Int>,
                        maxVal: Int, w: CGFloat, h: CGFloat) -> [CGPoint] {
        data.enumerated().map { i, pt in
            CGPoint(x: xPos(index: i, count: data.count, w: w),
                    y: yPos(value: pt[keyPath: keyPath], maxVal: maxVal, h: h))
        }
    }

    private func smoothPath(pts: [CGPoint]) -> Path {
        var path = Path()
        guard pts.count > 1 else { return path }
        path.move(to: pts[0])
        for i in 1..<pts.count {
            let prev = pts[i - 1]
            let curr = pts[i]
            let prevPrev = i > 1 ? pts[i - 2] : prev
            let next = i < pts.count - 1 ? pts[i + 1] : curr
            let cp1 = CGPoint(x: prev.x + (curr.x - prevPrev.x) / 6,
                              y: prev.y + (curr.y - prevPrev.y) / 6)
            let cp2 = CGPoint(x: curr.x - (next.x - prev.x) / 6,
                              y: curr.y - (next.y - prev.y) / 6)
            path.addCurve(to: curr, control1: cp1, control2: cp2)
        }
        return path
    }

    private func drawLine(ctx: GraphicsContext, w: CGFloat, h: CGFloat, maxVal: Int,
                          data: [MonthDataPoint], keyPath: KeyPath<MonthDataPoint, Int>,
                          color: Color, width: CGFloat, dash: [CGFloat] = []) {
        guard data.count > 1 else { return }
        let pts = points(data: data, keyPath: keyPath, maxVal: maxVal, w: w, h: h)
        ctx.stroke(smoothPath(pts: pts), with: .color(color),
                   style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round, dash: dash))
    }

    private func drawAreaFill(ctx: GraphicsContext, w: CGFloat, h: CGFloat, maxVal: Int,
                              data: [MonthDataPoint], keyPath: KeyPath<MonthDataPoint, Int>,
                              color: Color) {
        guard data.count > 1 else { return }
        let pts = points(data: data, keyPath: keyPath, maxVal: maxVal, w: w, h: h)
        var area = smoothPath(pts: pts)
        area.addLine(to: CGPoint(x: pts.last!.x, y: h))
        area.addLine(to: CGPoint(x: pts[0].x, y: h))
        area.closeSubpath()
        ctx.fill(area, with: .color(color.opacity(0.12)))
    }
}

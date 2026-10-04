import SwiftUI

/// A small, inline progress cue for live content. It deliberately has no
/// opaque container so the content around it remains visible while loading.
struct SignalTraceLoadingView: View {
    let lastUpdated: Date?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isAnimating = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { proxy in
                Capsule()
                    .fill(Theme.accent)
                    .frame(width: proxy.size.width * (reduceMotion ? 0.42 : 0.34), height: 2)
                    .offset(x: reduceMotion || !isAnimating ? 0 : proxy.size.width * 0.66)
                    .animation(
                        reduceMotion
                            ? nil
                            : .easeInOut(duration: 1.2).repeatForever(autoreverses: true),
                        value: isAnimating
                    )
            }
            .frame(height: 3)
            .clipped()

            if let lastUpdated {
                Text("Updated \(lastUpdated, style: .relative)")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.muted)
            }
        }
        .onAppear {
            guard !reduceMotion else { return }
            isAnimating = true
        }
        .accessibilityLabel("Updating")
        .accessibilityValue(lastUpdated.map { "Updated \($0.formatted(.relative(presentation: .named)))" } ?? "")
    }
}

/// The Settlr mark used while a request is in flight. Each bar pulses in
/// sequence only when the user has not requested reduced motion.
struct SettlrPulseLoadingView: View {
    let message: String
    let detail: String?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isAnimating = false

    init(message: String, detail: String? = nil) {
        self.message = message
        self.detail = detail
    }

    var body: some View {
        VStack(spacing: 14) {
            VStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(
                            reduceMotion
                                ? (index == 0 ? Theme.accent : Theme.muted.opacity(0.38))
                                : (isAnimating ? Theme.accent : Theme.muted.opacity(0.38))
                        )
                        .frame(width: 31, height: 5)
                        .offset(x: index == 1 ? 5 : 0)
                        .animation(
                            reduceMotion
                                ? nil
                                : .easeInOut(duration: 0.62)
                                    .repeatForever(autoreverses: true)
                                    .delay(Double(index) * 0.16),
                            value: isAnimating
                        )
                }
            }
            .frame(width: 65, height: 65)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Theme.surface2)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(Theme.line, lineWidth: 1)
                    )
            )

            VStack(spacing: 4) {
                Text(message)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(Theme.ink)

                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .onAppear {
            guard !reduceMotion else { return }
            isAnimating = true
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(message)
        .accessibilityValue(detail ?? "")
    }
}

/// Skeleton rows for the Activity timeline. The neutral nodes and bars retain
/// the timeline's shape without introducing a full-screen shimmer treatment.
struct ActivityShapeLoadingView: View {
    var body: some View {
        VStack(spacing: 18) {
            ForEach(0..<4, id: \.self) { row in
                HStack(alignment: .top, spacing: 12) {
                    Circle()
                        .fill(Theme.line)
                        .frame(width: 9, height: 9)
                        .padding(.top, 4)

                    VStack(alignment: .leading, spacing: 8) {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(Theme.surface2)
                            .frame(width: row.isMultiple(of: 2) ? 150 : 124, height: 11)
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(Theme.surface2)
                            .frame(width: row.isMultiple(of: 2) ? 92 : 112, height: 8)
                    }

                    Spacer(minLength: 0)
                }
            }
        }
        .accessibilityLabel("Loading activity")
    }
}

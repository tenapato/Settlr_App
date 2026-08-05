import SwiftUI

/// Shows the receipt you just captured with a scan line sweeping down it.
///
/// Reading a receipt takes a few seconds — OCR, then the model. A bare spinner
/// leaves you wondering whether the right photo was even taken, so the shot
/// itself is the progress indicator: you can see the receipt is in frame and
/// legible while the line sweeps it.
struct ScanningOverlay: View {
    let image: UIImage
    let message: String

    @State private var sweep: CGFloat = 0
    @State private var pulse = false

    private let cardWidth: CGFloat = 216
    private let cardHeight: CGFloat = 300

    var body: some View {
        ZStack {
            Color.black.opacity(0.86).ignoresSafeArea()

            VStack(spacing: 26) {
                receiptCard

                VStack(spacing: 8) {
                    Text(message)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .contentTransition(.opacity)
                        .animation(.easeInOut(duration: 0.25), value: message)
                    Text("Everything is read on your phone")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.faint)
                }
            }
        }
        .transition(.opacity)
        .onAppear {
            withAnimation(.linear(duration: 1.6).repeatForever(autoreverses: false)) {
                sweep = 1
            }
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }

    private var receiptCard: some View {
        Image(uiImage: image)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: cardWidth, height: cardHeight)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(scanLine)
            .overlay(corners)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Theme.accent.opacity(pulse ? 0.65 : 0.25), lineWidth: 1.5)
            )
            .shadow(color: Theme.accent.opacity(0.22), radius: 26, y: 8)
    }

    /// A lime band that sweeps top to bottom, with a soft gradient trailing it so
    /// it reads as a scan rather than a moving rectangle.
    private var scanLine: some View {
        GeometryReader { geo in
            let travel = geo.size.height + 60
            LinearGradient(
                colors: [
                    Theme.accent.opacity(0),
                    Theme.accent.opacity(0.28),
                    Theme.accent.opacity(0.95),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 60)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Theme.accent)
                    .frame(height: 2)
                    .shadow(color: Theme.accent.opacity(0.9), radius: 8)
            }
            .offset(y: -60 + travel * sweep)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .allowsHitTesting(false)
    }

    /// Viewfinder corner ticks, so the card reads as "being scanned".
    private var corners: some View {
        GeometryReader { geo in
            let length: CGFloat = 22
            ForEach(0..<4, id: \.self) { index in
                let isLeft = index % 2 == 0
                let isTop = index < 2
                Path { path in
                    let x: CGFloat = isLeft ? 10 : geo.size.width - 10
                    let y: CGFloat = isTop ? 10 : geo.size.height - 10
                    path.move(to: CGPoint(x: x, y: isTop ? y + length : y - length))
                    path.addLine(to: CGPoint(x: x, y: y))
                    path.addLine(to: CGPoint(x: isLeft ? x + length : x - length, y: y))
                }
                .stroke(Theme.accent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
            }
        }
        .allowsHitTesting(false)
    }
}

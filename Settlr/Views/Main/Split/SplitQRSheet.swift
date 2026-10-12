import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

/// A branded, table-readable handoff for the split's existing public URL.
struct SplitQRSheet: View {
    let link: URL
    let merchant: String

    @Environment(\.dismiss) private var dismiss
    @State private var copiedLink = false

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 18) {
                        VStack(spacing: 5) {
                            Text("Scan to join")
                                .font(.system(size: 22, weight: .bold))
                                .foregroundStyle(Theme.ink)
                            Text(merchant)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(Theme.muted)
                        }
                        .frame(maxWidth: .infinity)

                        if let image = SplitQRCode.image(for: link) {
                            ZStack {
                                Image(uiImage: image)
                                    .interpolation(.none)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxWidth: 320)

                                if SplitQRCode.reservesCenterBranding {
                                    Image("SettlrLogo")
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 60, height: 60)
                                        .padding(6)
                                        .background(Color.white)
                                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                        .accessibilityHidden(true)
                                }
                            }
                            .padding(16)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("QR code to join the bill split for \(merchant)")
                            .accessibilityAddTraits(.isImage)
                        } else {
                            Text("This link couldn't be turned into a QR code. Copy the link or share it instead.")
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.muted)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
                        }

                        VStack(spacing: 10) {
                            Text(link.absoluteString)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(Theme.faint)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                                .textSelection(.enabled)

                            HStack(spacing: 10) {
                                Button { copyLink() } label: {
                                    Label(copiedLink ? "Copied" : "Copy link", systemImage: copiedLink ? "checkmark" : "doc.on.doc")
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(Theme.ink)
                                        .frame(maxWidth: .infinity)
                                        .frame(minHeight: 44)
                                        .background(Theme.surface2)
                                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                }
                                .buttonStyle(.plain)

                                ShareLink(item: link.absoluteString) {
                                    Label("Share", systemImage: "square.and.arrow.up")
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(Theme.buttonInk)
                                        .frame(maxWidth: .infinity)
                                        .frame(minHeight: 44)
                                        .background(Theme.accent)
                                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                }
                            }
                        }
                        .padding(14)
                        .background(Theme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(Theme.line, lineWidth: 1)
                        )
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Join the split")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Theme.accentText)
                        .frame(minHeight: 44)
                }
            }
        }
    }

    private func copyLink() {
        UIPasteboard.general.string = link.absoluteString
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        withAnimation(.easeOut(duration: 0.15)) { copiedLink = true }
        Task {
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            withAnimation(.easeOut(duration: 0.2)) { copiedLink = false }
        }
    }
}

enum SplitQRCode {
    /// High correction plus a reserved center plate keeps the logo from
    /// covering data modules. The plate is drawn into the bitmap before the
    /// optional logo is placed by the sheet.
    static let correctionLevel = "H"
    static let protectedCenterModules = 9
    static var reservesCenterBranding: Bool {
        correctionLevel == "H" && protectedCenterModules >= 7
    }

    @MainActor private static let context = CIContext()

    /// Returns nil rather than a placeholder when generation fails, so the
    /// caller can fall back to the plain share URL.
    @MainActor static func image(for link: URL) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(link.absoluteString.utf8)
        filter.correctionLevel = correctionLevel

        guard let output = filter.outputImage else { return nil }
        let moduleScale: CGFloat = 12
        let scaled = output.transformed(by: CGAffineTransform(scaleX: moduleScale, y: moduleScale))
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }

        let size = CGSize(width: cgImage.width, height: cgImage.height)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { rendererContext in
            UIColor.white.setFill()
            rendererContext.fill(CGRect(origin: .zero, size: size))
            UIImage(cgImage: cgImage).draw(in: CGRect(origin: .zero, size: size))

            if reservesCenterBranding {
                let plateSize = moduleScale * CGFloat(protectedCenterModules)
                let plateRect = CGRect(
                    x: (size.width - plateSize) / 2,
                    y: (size.height - plateSize) / 2,
                    width: plateSize,
                    height: plateSize
                )
                UIColor.white.setFill()
                UIBezierPath(roundedRect: plateRect, cornerRadius: moduleScale).fill()
            }
        }
    }
}

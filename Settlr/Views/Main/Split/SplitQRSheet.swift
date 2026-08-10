import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

/// The share link as a QR code, sized to be scanned across a table.
///
/// At a restaurant, sending a link through a messaging app means finding six
/// people in your contacts while the waiter waits. Holding up the phone is one
/// gesture and everybody joins at once — the same link, just handed over at the
/// speed the moment actually runs at.
///
/// Generated on-device with CoreImage; nothing about the split leaves the phone
/// to make the image.
struct SplitQRSheet: View {
    let link: URL
    let merchant: String

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()
                VStack(spacing: 20) {
                    Text("Scan to join the split")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.muted)

                    if let image = SplitQRCode.image(for: link) {
                        Image(uiImage: image)
                            .interpolation(.none) // keep the modules crisp when scaled up
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 300)
                            .padding(16)
                            // A QR needs a light quiet zone to scan reliably, so this
                            // one panel stays light even in the dark theme.
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    } else {
                        Text("This link couldn't be turned into a QR code. Send it instead.")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.muted)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }

                    Text(merchant)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.ink)

                    Text(link.absoluteString)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Theme.faint)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)

                    Spacer()
                }
                .padding(.top, 24)
            }
            .navigationTitle("Join the split")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.foregroundStyle(Theme.accent)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

enum SplitQRCode {
    /// Shared across calls: `CIContext` is expensive to build and this one is
    /// only ever touched from the main actor while a sheet is on screen.
    @MainActor private static let context = CIContext()

    /// Returns nil rather than a placeholder when generation fails, so the caller
    /// can fall back to the link instead of showing an unscannable square.
    @MainActor static func image(for link: URL) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(link.absoluteString.utf8)
        // Medium correction: survives a thumb over one corner without inflating
        // the module count enough to hurt scanning across a table.
        filter.correctionLevel = "M"

        guard let output = filter.outputImage else { return nil }
        // CoreImage emits roughly one pixel per module; scale up before rasterising
        // so the bitmap isn't blurred by the view's own interpolation.
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 12, y: 12))
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

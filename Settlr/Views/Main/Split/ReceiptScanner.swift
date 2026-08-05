import UIKit
import Vision

/// On-device receipt reading.
///
/// The photo never leaves the phone: Vision finds the receipt in the frame,
/// straightens it, and reads the text locally. Only that text is sent to the
/// server for structuring, so receipt images stay off our infrastructure and we
/// don't need a vision model.
enum ReceiptOCR {
    /// Recognises a receipt top-to-bottom, left-to-right so item names stay next
    /// to their prices in the text the parser sees.
    static func recognizeText(in image: UIImage) throws -> String {
        guard let cgImage = image.cgImage else { throw ReceiptScanError.noTextFound }
        let straightened = deskewedDocument(in: cgImage) ?? cgImage

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false // menu items aren't dictionary words
        request.recognitionLanguages = ["es-MX", "en-US"]

        try VNImageRequestHandler(cgImage: straightened, options: [:]).perform([request])

        let lines: [(y: CGFloat, x: CGFloat, text: String)] = (request.results ?? []).compactMap {
            guard let candidate = $0.topCandidates(1).first else { return nil }
            return (y: $0.boundingBox.midY, x: $0.boundingBox.minX, text: candidate.string)
        }
        let text = lines
            // Vision's origin is bottom-left, so descending Y is top-down.
            .sorted { $0.y == $1.y ? $0.x < $1.x : $0.y > $1.y }
            .map(\.text)
            .joined(separator: "\n")

        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ReceiptScanError.noTextFound
        }
        return text
    }

    /// Crops to the receipt and corrects perspective, which is most of what a
    /// document scanner buys you. Returns nil when no document is found, so the
    /// caller can fall back to reading the whole frame.
    private static func deskewedDocument(in image: CGImage) -> CGImage? {
        let request = VNDetectDocumentSegmentationRequest()
        guard (try? VNImageRequestHandler(cgImage: image, options: [:]).perform([request])) != nil,
              let observation = request.results?.first
        else { return nil }

        let ciImage = CIImage(cgImage: image)
        let size = ciImage.extent.size
        func point(_ normalized: CGPoint) -> CIVector {
            CIVector(x: normalized.x * size.width, y: normalized.y * size.height)
        }

        guard let filter = CIFilter(name: "CIPerspectiveCorrection") else { return nil }
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(point(observation.topLeft), forKey: "inputTopLeft")
        filter.setValue(point(observation.topRight), forKey: "inputTopRight")
        filter.setValue(point(observation.bottomLeft), forKey: "inputBottomLeft")
        filter.setValue(point(observation.bottomRight), forKey: "inputBottomRight")

        guard let output = filter.outputImage else { return nil }
        return CIContext().createCGImage(output, from: output.extent)
    }
}

enum ReceiptScanError: LocalizedError {
    case cameraUnavailable
    case cameraDenied
    case captureFailed
    case noTextFound

    var errorDescription: String? {
        switch self {
        case .cameraUnavailable:
            return "This device has no camera. Choose a receipt photo instead, or add the items by hand."
        case .cameraDenied:
            return "Settlr needs camera access to scan a receipt. Turn it on in Settings, or choose a photo you already took."
        case .captureFailed:
            return "That photo didn't come through. Try again."
        case .noTextFound:
            return "No text was readable on that photo. Try again in better light, or add the items by hand."
        }
    }
}

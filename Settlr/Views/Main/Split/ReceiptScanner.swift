import UIKit
import Vision

/// On-device receipt reading.
///
/// The photo never leaves the phone: Vision finds the receipt in the frame,
/// straightens it, and reads the text locally. Only that text is sent to the
/// server for structuring, so receipt images stay off our infrastructure and we
/// don't need a vision model.
enum ReceiptOCR {
    /// Recognises a receipt as rows, so each item's name stays on the same line as
    /// its price in the text the parser sees.
    static func recognizeText(in image: UIImage) throws -> String {
        guard let cgImage = image.cgImage else { throw ReceiptScanError.noTextFound }
        let straightened = deskewedDocument(in: cgImage) ?? cgImage

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false // menu items aren't dictionary words
        request.recognitionLanguages = ["es-MX", "en-US"]

        try VNImageRequestHandler(cgImage: straightened, options: [:]).perform([request])

        let fragments: [Fragment] = (request.results ?? []).compactMap {
            guard let candidate = $0.topCandidates(1).first else { return nil }
            return Fragment(box: $0.boundingBox, text: candidate.string)
        }

        let text = groupIntoRows(fragments)
            .map { row in
                row.sorted { $0.box.minX < $1.box.minX }
                    .map(\.text)
                    .joined(separator: "   ")
            }
            .joined(separator: "\n")

        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ReceiptScanError.noTextFound
        }
        return text
    }

    private struct Fragment {
        let box: CGRect
        let text: String
    }

    /// Puts text fragments that sit on the same printed line back together.
    ///
    /// Vision reports each column as its own observation, so an item's name and
    /// its price arrive separately. Emitting one fragment per line loses the
    /// pairing: the columns have slightly different baselines, so a price can
    /// sort ahead of its own name and land against the item above it — which is
    /// how a 300-peso ramen ends up printed against a soft drink. Worse, the
    /// mistake isn't stable, so two photos of one receipt disagree.
    ///
    /// Rows are cut by vertical overlap rather than by distance between
    /// midpoints, so a large bold total still groups with its small-text label.
    /// Rotation is `deskewedDocument`'s job; this assumes lines are level.
    private static func groupIntoRows(_ fragments: [Fragment]) -> [[Fragment]] {
        // Vision's origin is bottom-left, so descending Y walks the receipt down.
        let ordered = fragments.sorted { $0.box.midY > $1.box.midY }

        var rows: [[Fragment]] = []
        for fragment in ordered {
            // Compared against the row's first fragment, never the last one
            // added: chaining off the last would let a row creep down the
            // receipt one tolerance at a time and swallow the line below.
            if let anchor = rows.last?.first, sharesRow(anchor.box, fragment.box) {
                rows[rows.count - 1].append(fragment)
            } else {
                rows.append([fragment])
            }
        }
        return rows
    }

    /// Two fragments are on one printed line when their vertical extents overlap
    /// by more than a third of the shorter one. Adjacent lines clear each other
    /// comfortably at that threshold, even on a tightly printed receipt.
    private static func sharesRow(_ a: CGRect, _ b: CGRect) -> Bool {
        let overlap = min(a.maxY, b.maxY) - max(a.minY, b.minY)
        return overlap > 0.35 * min(a.height, b.height)
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

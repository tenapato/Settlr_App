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
        guard let upright = uprightPixels(of: image) else { throw ReceiptScanError.noTextFound }

        var best = read(upright)
        // A receipt lying sideways on the table defeats row grouping outright:
        // every printed row becomes a vertical strip, so they all overlap in Y
        // and collapse into one or two enormous lines. Re-reading turned is
        // expensive, so it is gated on that state actually being detected —
        // measured on real photos it scores ~0.03 rows per fragment against
        // ~0.45 upright, which is a wide enough margin to act on.
        if best.isDegenerate {
            for turn in [ExifTurn.quarterClockwise, .quarterCounterClockwise] {
                let candidate = read(turned(upright, turn))
                if candidate.rows.count > best.rows.count { best = candidate }
            }
        }

        let text = best.text
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ReceiptScanError.noTextFound
        }
        return text
    }

    private struct Fragment {
        let box: CGRect
        let text: String
    }

    /// One attempt at reading the frame, kept whole so attempts can be compared
    /// before either is turned into text.
    private struct Reading {
        let rows: [[Fragment]]
        let fragmentCount: Int

        var text: String {
            rows
                .map { row in
                    row.sorted { $0.box.minX < $1.box.minX }
                        .map(\.text)
                        .joined(separator: "   ")
                }
                .joined(separator: "\n")
        }

        /// Rows per fragment. An upright receipt lands around 0.45; sideways text
        /// collapses to 0.03 because every printed row overlaps every other one
        /// in Y. Below a fifth, the geometry is telling us the lines aren't level.
        var isDegenerate: Bool {
            fragmentCount >= 8 && rows.count * 5 < fragmentCount
        }
    }

    private static func read(_ image: CGImage) -> Reading {
        let straightened = deskewedDocument(in: image) ?? image

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false // menu items aren't dictionary words
        request.recognitionLanguages = ["es-MX", "en-US"]

        try? VNImageRequestHandler(cgImage: straightened, options: [:]).perform([request])

        let fragments: [Fragment] = (request.results ?? []).compactMap {
            guard let candidate = $0.topCandidates(1).first else { return nil }
            return Fragment(box: $0.boundingBox, text: candidate.string)
        }
        return Reading(rows: groupIntoRows(fragments), fragmentCount: fragments.count)
    }

    /// Bakes `imageOrientation` into the pixels before Vision sees them.
    ///
    /// `UIImage.cgImage` hands back the raw sensor buffer and silently drops the
    /// orientation flag. A photo taken with the phone held upright carries EXIF
    /// orientation 6 — as does anything picked out of the camera roll — so the
    /// receipt reached Vision turned a quarter turn. Every printed row then ran
    /// vertically, all of them overlapped in Y, and grouping merged a 24-item
    /// receipt into two lines: one holding every name, one holding every price.
    /// The parser was left pairing two lists by guesswork, and `applyPrinted`
    /// took the rightmost money on the price line — the grand total — as the
    /// first item's price.
    ///
    /// Drawing through `UIImage.draw(in:)` rather than mapping
    /// `UIImage.Orientation` onto `CGImagePropertyOrientation` by hand: the two
    /// enums disagree about what "left" means, and UIKit already knows.
    private static func uprightPixels(of image: UIImage) -> CGImage? {
        guard image.imageOrientation != .up else { return image.cgImage }

        let format = UIGraphicsImageRendererFormat.preferred()
        format.scale = image.scale // keep every pixel; OCR needs the detail
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
        let redrawn = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
        return redrawn.cgImage ?? image.cgImage
    }

    /// EXIF orientation values, named by the turn they apply.
    private enum ExifTurn: Int32 {
        case quarterClockwise = 6
        case quarterCounterClockwise = 8
    }

    private static func turned(_ image: CGImage, _ turn: ExifTurn) -> CGImage {
        let rotated = CIImage(cgImage: image).oriented(forExifOrientation: turn.rawValue)
        return CIContext().createCGImage(rotated, from: rotated.extent) ?? image
    }

    /// Puts text fragments that sit on the same printed line back together.
    ///
    /// Vision reports each column as its own observation, so an item's quantity,
    /// name and price all arrive separately and have to be paired by geometry.
    ///
    /// Each printed line is seeded by its widest fragment — on an item line that
    /// is the name, which is also the tallest and steadiest box — and every other
    /// fragment then joins the seed it overlaps *most*. Taking the maximum rather
    /// than the first acceptable match is the whole point. Price boxes sit
    /// slightly higher than the name they belong to, so a wrapped continuation
    /// line (the "BCO" under "TEQUILA SIETE LEGUAS") used to be tested first and
    /// accepted, stealing the price off the line below and shifting every price
    /// after it by one row until a gap resynchronised it.
    ///
    /// Clustering on Y centres cannot fix that: measured on a real receipt, the
    /// gap between two rows (0.0080) was smaller than a gap inside one (0.0064).
    /// Only the boxes' extents carry enough information, and only if every
    /// candidate line is considered.
    ///
    /// Rotation is `uprightPixels`' job; this assumes lines are level.
    private static func groupIntoRows(_ fragments: [Fragment]) -> [[Fragment]] {
        let widestFirst = fragments.indices.sorted {
            fragments[$0].box.width > fragments[$1].box.width
        }
        var seeds: [Int] = []
        for index in widestFirst {
            let box = fragments[index].box
            let alreadyOnALine = seeds.contains { seed in
                verticalOverlap(fragments[seed].box, box)
                    > 0.5 * min(fragments[seed].box.height, box.height)
            }
            if !alreadyOnALine { seeds.append(index) }
        }

        var rows: [[Fragment]] = seeds.map { [fragments[$0]] }
        // A token touching no line at all keeps its own row rather than being
        // forced onto the nearest one, which is how stray marks used to become
        // part of an item's name.
        var orphans: [[Fragment]] = []
        let seeded = Set(seeds)

        for (index, fragment) in fragments.enumerated() where !seeded.contains(index) {
            var bestRow: Int?
            var bestOverlap: CGFloat = 0
            for (row, members) in rows.enumerated() {
                let overlap = verticalOverlap(members[0].box, fragment.box)
                if overlap > bestOverlap {
                    bestOverlap = overlap
                    bestRow = row
                }
            }
            if let bestRow,
               bestOverlap > 0.15 * min(rows[bestRow][0].box.height, fragment.box.height) {
                rows[bestRow].append(fragment)
            } else {
                orphans.append([fragment])
            }
        }

        // Vision's origin is bottom-left, so descending Y walks the receipt down.
        // Every row is ordered by its seed, which never moves off index 0.
        return (rows + orphans).sorted { $0[0].box.midY > $1[0].box.midY }
    }

    private static func verticalOverlap(_ a: CGRect, _ b: CGRect) -> CGFloat {
        max(0, min(a.maxY, b.maxY) - max(a.minY, b.minY))
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

import Foundation
import UIKit

enum ReceiptPhotoUploadError: LocalizedError, Equatable {
    case couldNotEncode
    case imageTooLarge

    var errorDescription: String? {
        switch self {
        case .couldNotEncode:
            "The receipt photo could not be prepared. Choose another photo and try again."
        case .imageTooLarge:
            "The receipt photo is too large. Choose another photo and try again."
        }
    }
}

struct PreparedReceiptPhoto: Equatable {
    let jpegData: Data
    let pixelWidth: Int
    let pixelHeight: Int
}

enum ReceiptPhotoUpload {
    static let maxLongestEdge = 2048
    static let jpegQuality: CGFloat = 0.8
    static let maxBytes = 6 * 1024 * 1024

    static func prepare(_ image: UIImage) throws -> PreparedReceiptPhoto {
        try prepare(image) { rendered, quality in
            rendered.jpegData(compressionQuality: quality)
        }
    }

    /// The injectable encoder keeps final-byte validation deterministic in
    /// tests while production still performs exactly one JPEG encoding pass.
    static func prepare(
        _ image: UIImage,
        jpegEncoder: (UIImage, CGFloat) -> Data?
    ) throws -> PreparedReceiptPhoto {
        let source = orientedPixelSize(of: image)
        guard source.width > 0, source.height > 0 else {
            throw ReceiptPhotoUploadError.couldNotEncode
        }

        let longestEdge = max(source.width, source.height)
        let scale = min(1, CGFloat(maxLongestEdge) / longestEdge)
        let pixelWidth = max(1, Int((source.width * scale).rounded()))
        let pixelHeight = max(1, Int((source.height * scale).rounded()))
        let targetSize = CGSize(width: pixelWidth, height: pixelHeight)

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let normalized = UIGraphicsImageRenderer(size: targetSize, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: targetSize))
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }

        guard let jpegData = jpegEncoder(normalized, jpegQuality), !jpegData.isEmpty else {
            throw ReceiptPhotoUploadError.couldNotEncode
        }
        guard jpegData.count <= maxBytes else {
            throw ReceiptPhotoUploadError.imageTooLarge
        }
        return PreparedReceiptPhoto(
            jpegData: jpegData,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight
        )
    }

    static func multipartBody(
        boundary: String,
        photo: PreparedReceiptPhoto,
        ocrText: String
    ) -> Data {
        var body = Data()
        body.appendUTF8("--\(boundary)\r\n")
        body.appendUTF8("Content-Disposition: form-data; name=\"photo\"; filename=\"receipt.jpg\"\r\n")
        body.appendUTF8("Content-Type: image/jpeg\r\n\r\n")
        body.append(photo.jpegData)
        body.appendUTF8("\r\n")
        body.appendUTF8("--\(boundary)\r\n")
        body.appendUTF8("Content-Disposition: form-data; name=\"text\"\r\n")
        body.appendUTF8("Content-Type: text/plain; charset=utf-8\r\n\r\n")
        body.appendUTF8(ocrText)
        body.appendUTF8("\r\n--\(boundary)--\r\n")
        return body
    }

    private static func orientedPixelSize(of image: UIImage) -> CGSize {
        let rawWidth = CGFloat(image.cgImage?.width ?? Int((image.size.width * image.scale).rounded()))
        let rawHeight = CGFloat(image.cgImage?.height ?? Int((image.size.height * image.scale).rounded()))
        switch image.imageOrientation {
        case .left, .leftMirrored, .right, .rightMirrored:
            return CGSize(width: rawHeight, height: rawWidth)
        default:
            return CGSize(width: rawWidth, height: rawHeight)
        }
    }
}

private extension Data {
    mutating func appendUTF8(_ value: String) {
        append(contentsOf: value.utf8)
    }
}

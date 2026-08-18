import UIKit
import XCTest
@testable import Settlr

final class ReceiptPhotoUploadTests: XCTestCase {
    func testPrepareCapsLandscapeLongestEdgeAndUsesRequiredJPEGQuality() throws {
        let source = image(width: 4_000, height: 2_000)
        var encodedSize: CGSize?
        var encodedQuality: CGFloat?

        let prepared = try ReceiptPhotoUpload.prepare(source) { rendered, quality in
            encodedSize = rendered.size
            encodedQuality = quality
            return Data([0xff, 0xd8, 0xff, 0xd9])
        }

        XCTAssertEqual(prepared.pixelWidth, 2_048)
        XCTAssertEqual(prepared.pixelHeight, 1_024)
        XCTAssertEqual(encodedSize, CGSize(width: 2_048, height: 1_024))
        XCTAssertEqual(encodedQuality, 0.8)
    }

    func testPrepareCapsPortraitLongestEdgeAndPreservesAspectRatio() throws {
        let source = image(width: 1_000, height: 3_000)

        let prepared = try ReceiptPhotoUpload.prepare(source) { _, _ in Data([1]) }

        XCTAssertEqual(prepared.pixelWidth, 683)
        XCTAssertEqual(prepared.pixelHeight, 2_048)
    }

    func testPrepareNormalizesWithoutUpscalingSmallImage() throws {
        let source = image(width: 640, height: 480)

        let prepared = try ReceiptPhotoUpload.prepare(source) { rendered, _ in
            XCTAssertEqual(rendered.imageOrientation, .up)
            return Data([1])
        }

        XCTAssertEqual(prepared.pixelWidth, 640)
        XCTAssertEqual(prepared.pixelHeight, 480)
    }

    func testPrepareUsesDisplayedDimensionsForLeftAndRightOrientationFixtures() throws {
        let base = quadrantImage(width: 600, height: 1_200)
        let left = UIImage(cgImage: base.cgImage!, scale: 1, orientation: .left)
        let right = UIImage(cgImage: base.cgImage!, scale: 1, orientation: .right)

        let preparedLeft = try ReceiptPhotoUpload.prepare(left) { rendered, _ in
            XCTAssertEqual(rendered.imageOrientation, .up)
            assertQuadrantPixels(in: rendered, expectedTopLeft: .red, expectedBottomRight: .green)
            return Data([1])
        }
        let preparedRight = try ReceiptPhotoUpload.prepare(right) { rendered, _ in
            XCTAssertEqual(rendered.imageOrientation, .up)
            assertQuadrantPixels(in: rendered, expectedTopLeft: .green, expectedBottomRight: .red)
            return Data([1])
        }

        XCTAssertEqual(preparedLeft.pixelWidth, 2_048)
        XCTAssertEqual(preparedLeft.pixelHeight, 1_024)
        XCTAssertEqual(preparedRight.pixelWidth, 2_048)
        XCTAssertEqual(preparedRight.pixelHeight, 1_024)
    }

    func testPrepareNormalizesMirroredOrientationFixtures() throws {
        let base = quadrantImage(width: 400, height: 800)
        let mirrored = UIImage(cgImage: base.cgImage!, scale: 1, orientation: .upMirrored)
        let mirroredDown = UIImage(cgImage: base.cgImage!, scale: 1, orientation: .downMirrored)

        let prepared = try ReceiptPhotoUpload.prepare(mirrored) { rendered, _ in
            XCTAssertEqual(rendered.imageOrientation, .up)
            assertQuadrantPixels(in: rendered, expectedTopLeft: .red, expectedBottomRight: .green)
            return Data([1])
        }
        let preparedDown = try ReceiptPhotoUpload.prepare(mirroredDown) { rendered, _ in
            XCTAssertEqual(rendered.imageOrientation, .up)
            assertQuadrantPixels(in: rendered, expectedTopLeft: .green, expectedBottomRight: .red)
            return Data([1])
        }

        XCTAssertEqual(prepared.pixelWidth, 400)
        XCTAssertEqual(prepared.pixelHeight, 800)
        XCTAssertEqual(preparedDown.pixelWidth, 400)
        XCTAssertEqual(preparedDown.pixelHeight, 800)
    }

    func testPrepareRejectsDeterministicallyOversizedJPEG() {
        let source = image(width: 10, height: 10)

        XCTAssertThrowsError(
            try ReceiptPhotoUpload.prepare(source) { _, _ in
                Data(count: ReceiptPhotoUpload.maxBytes + 1)
            }
        ) { error in
            XCTAssertEqual(error as? ReceiptPhotoUploadError, .imageTooLarge)
        }
    }

    func testPrepareRejectsFailedEncoding() {
        XCTAssertThrowsError(
            try ReceiptPhotoUpload.prepare(image(width: 10, height: 10)) { _, _ in nil }
        ) { error in
            XCTAssertEqual(error as? ReceiptPhotoUploadError, .couldNotEncode)
        }
    }

    func testMultipartContainsOnlyRawJPEGPhotoAndUTF8TextParts() {
        let jpeg = Data([0xff, 0xd8, 0x00, 0xfe, 0xff, 0xd9])
        let photo = PreparedReceiptPhoto(jpegData: jpeg, pixelWidth: 10, pixelHeight: 20)
        let boundary = "settlr-test-boundary"

        let body = ReceiptPhotoUpload.multipartBody(
            boundary: boundary,
            photo: photo,
            ocrText: "1 café — $50"
        )
        let text = String(decoding: body, as: UTF8.self)

        XCTAssertTrue(text.contains("Content-Disposition: form-data; name=\"photo\"; filename=\"receipt.jpg\"\r\n"))
        XCTAssertTrue(text.contains("Content-Type: image/jpeg\r\n"))
        XCTAssertTrue(text.contains("Content-Disposition: form-data; name=\"text\"\r\n"))
        XCTAssertTrue(text.contains("Content-Type: text/plain; charset=utf-8\r\n"))
        XCTAssertTrue(text.contains("1 café — $50"))
        XCTAssertTrue(body.range(of: jpeg) != nil)
        XCTAssertFalse(text.contains(jpeg.base64EncodedString()))
        XCTAssertEqual(text.components(separatedBy: "Content-Disposition: form-data;").count - 1, 2)
        XCTAssertTrue(body.suffix(Data("--\(boundary)--\r\n".utf8).count) == Data("--\(boundary)--\r\n".utf8))
    }

    private func image(width: Int, height: Int) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(
            size: CGSize(width: width, height: height),
            format: format
        ).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    private func quadrantImage(width: Int, height: Int) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
            let half = CGSize(width: width / 2, height: height / 2)
            UIColor.blue.setFill(); context.fill(CGRect(origin: .zero, size: half))
            UIColor.red.setFill(); context.fill(CGRect(x: width / 2, y: 0, width: half.width, height: half.height))
            UIColor.green.setFill(); context.fill(CGRect(x: 0, y: height / 2, width: half.width, height: half.height))
            UIColor.yellow.setFill(); context.fill(CGRect(x: width / 2, y: height / 2, width: half.width, height: half.height))
        }
    }

    private func assertQuadrantPixels(
        in image: UIImage,
        expectedTopLeft: UIColor,
        expectedBottomRight: UIColor
    ) {
        guard let cgImage = image.cgImage,
              let provider = cgImage.dataProvider,
              let data = provider.data,
              let bytes = CFDataGetBytePtr(data)
        else {
            XCTFail("Expected normalized image pixels")
            return
        }
        let bytesPerPixel = cgImage.bitsPerPixel / 8
        func rgb(atX x: Int, y: Int) -> (CGFloat, CGFloat, CGFloat) {
            let offset = y * cgImage.bytesPerRow + x * bytesPerPixel
            if cgImage.bitmapInfo.contains(.byteOrder32Little) {
                return (CGFloat(bytes[offset + 2]) / 255, CGFloat(bytes[offset + 1]) / 255, CGFloat(bytes[offset]) / 255)
            }
            return (CGFloat(bytes[offset]) / 255, CGFloat(bytes[offset + 1]) / 255, CGFloat(bytes[offset + 2]) / 255)
        }
        func assertColor(_ actual: (CGFloat, CGFloat, CGFloat), equals expected: UIColor) {
            var red: CGFloat = 0
            var green: CGFloat = 0
            var blue: CGFloat = 0
            var alpha: CGFloat = 0
            XCTAssertTrue(expected.getRed(&red, green: &green, blue: &blue, alpha: &alpha))
            XCTAssertEqual(actual.0, red, accuracy: 0.02)
            XCTAssertEqual(actual.1, green, accuracy: 0.02)
            XCTAssertEqual(actual.2, blue, accuracy: 0.02)
        }
        assertColor(rgb(atX: cgImage.width / 4, y: cgImage.height / 4), equals: expectedTopLeft)
        assertColor(rgb(atX: cgImage.width * 3 / 4, y: cgImage.height * 3 / 4), equals: expectedBottomRight)
    }
}

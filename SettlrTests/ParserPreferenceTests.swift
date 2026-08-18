import XCTest
import UIKit
@testable import Settlr

@MainActor
final class ParserPreferenceTests: XCTestCase {
    func testAutomaticUsesValidOnDeviceResultWithoutCallingServer() async throws {
        var serverCalled = false
        let router = ReceiptParserRouter(
            onDevice: { _ in self.receipt(parser: .onDevice) },
            server: { _ in
                serverCalled = true
                return self.receipt(parser: .server)
            }
        )

        let result = try await router.parse("1 TACO 50.00", preference: .automatic)

        XCTAssertEqual(result.parser, .onDevice)
        XCTAssertFalse(serverCalled)
    }

    func testAutomaticFallsBackToServerWhenDeviceHasNoUsableRows() async throws {
        var serverCalled = false
        let empty = receipt(parser: .onDevice, items: [])
        let router = ReceiptParserRouter(
            onDevice: { _ in empty },
            server: { _ in
                serverCalled = true
                return self.receipt(parser: .server)
            }
        )

        let result = try await router.parse("1 TACO 50.00", preference: .automatic)

        XCTAssertEqual(result.parser, .server)
        XCTAssertTrue(serverCalled)
    }

    func testAutomaticFallbackUsesTextServerEvenWhenPhotoIsAvailable() async throws {
        var serverCalled = false
        var photoCalled = false
        let router = ReceiptParserRouter(
            onDevice: { _ in throw ReceiptParserRoutingError.onDeviceFailed },
            server: { _ in
                serverCalled = true
                return self.receipt(parser: .server)
            },
            serverPhoto: { _, _ in
                photoCalled = true
                return self.receipt(parser: .serverPhoto)
            }
        )

        let result = try await router.parse("recognized rows", preference: .automatic, image: UIImage())

        XCTAssertEqual(result.parser, .server)
        XCTAssertTrue(serverCalled)
        XCTAssertFalse(photoCalled)
    }

    func testOnDevicePreferenceNeverCallsServerWhenDeviceIsUnavailable() async {
        var serverCalled = false
        let router = ReceiptParserRouter(
            onDevice: { _ in nil },
            server: { _ in
                serverCalled = true
                return self.receipt(parser: .server)
            }
        )

        do {
            _ = try await router.parse("private OCR text", preference: .onDevice)
            XCTFail("Expected on-device-only parsing to fail")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("Automatic"))
            XCTAssertTrue(error.localizedDescription.contains("On server"))
        }
        XCTAssertFalse(serverCalled)
    }

    func testServerPreferenceSendsOnlyRecognizedTextToServerParser() async throws {
        var receivedText: String?
        var onDeviceCalled = false
        let router = ReceiptParserRouter(
            onDevice: { _ in
                onDeviceCalled = true
                return self.receipt(parser: .onDevice)
            },
            server: { text in
                receivedText = text
                return self.receipt(parser: .server)
            }
        )

        let result = try await router.parse("recognized rows only", preference: .server)

        XCTAssertEqual(receivedText, "recognized rows only")
        XCTAssertFalse(onDeviceCalled)
        XCTAssertEqual(result.parser, .server)
    }

    func testServerTextKeepsDeterministicServerPriceWhenLocalOCRDisagrees() async throws {
        let serverReceipt = receipt(
            parser: .server,
            items: [
                ScannedReceiptItem(
                    name: "TACO",
                    quantity: 1,
                    unitPriceCents: 10_500,
                    verification: .verified
                )
            ]
        )
        let router = ReceiptParserRouter(
            onDevice: { _ in XCTFail("device should not run"); return nil },
            server: { _ in serverReceipt }
        )

        let result = try await router.parse("TACO 15.00", preference: .server)

        XCTAssertEqual(result.items.first?.unitPriceCents, 10_500)
        XCTAssertEqual(result.items.first?.verification, .verified)
    }

    func testServerPhotoKeepsDeterministicServerPriceWhenLocalOCRDisagrees() async throws {
        let serverReceipt = receipt(
            parser: .serverPhoto,
            items: [
                ScannedReceiptItem(
                    name: "TACO",
                    quantity: 1,
                    unitPriceCents: 10_500,
                    verification: .verified
                )
            ]
        )
        let router = ReceiptParserRouter(
            onDevice: { _ in XCTFail("device should not run"); return nil },
            server: { _ in XCTFail("text server should not run"); return nil },
            preparePhoto: { _ in self.preparedPhoto() },
            serverPhoto: { _, _ in serverReceipt }
        )

        let result = try await router.parse(
            "TACO 15.00",
            preference: .serverPhoto,
            image: UIImage()
        )

        XCTAssertEqual(result.items.first?.unitPriceCents, 10_500)
        XCTAssertEqual(result.items.first?.verification, .verified)
    }

    func testAutomaticNeverCallsPhotoParser() async throws {
        var photoCalled = false
        let router = ReceiptParserRouter(
            onDevice: { _ in self.receipt(parser: .onDevice) },
            server: { _ in self.receipt(parser: .server) },
            serverPhoto: { _, _ in
                photoCalled = true
                return self.receipt(parser: .serverPhoto)
            }
        )

        _ = try await router.parse("recognized rows", preference: .automatic, image: UIImage())

        XCTAssertFalse(photoCalled)
    }

    func testOnDeviceNeverCallsPhotoParser() async throws {
        var photoCalled = false
        let router = ReceiptParserRouter(
            onDevice: { _ in self.receipt(parser: .onDevice) },
            server: { _ in self.receipt(parser: .server) },
            serverPhoto: { _, _ in
                photoCalled = true
                return self.receipt(parser: .serverPhoto)
            }
        )

        _ = try await router.parse("recognized rows", preference: .onDevice, image: UIImage())

        XCTAssertFalse(photoCalled)
    }

    func testServerNeverCallsPhotoParser() async throws {
        var photoCalled = false
        let router = ReceiptParserRouter(
            onDevice: { _ in self.receipt(parser: .onDevice) },
            server: { _ in self.receipt(parser: .server) },
            serverPhoto: { _, _ in
                photoCalled = true
                return self.receipt(parser: .serverPhoto)
            }
        )

        _ = try await router.parse("recognized rows", preference: .server, image: UIImage())

        XCTAssertFalse(photoCalled)
    }

    func testServerPhotoRequiresImageAndUsesOnlyPhotoParser() async throws {
        var serverCalled = false
        var photoCalled = false
        let router = ReceiptParserRouter(
            onDevice: { _ in self.receipt(parser: .onDevice) },
            server: { _ in
                serverCalled = true
                return self.receipt(parser: .server)
            },
            preparePhoto: { _ in self.preparedPhoto() },
            serverPhoto: { _, _ in
                photoCalled = true
                return self.receipt(parser: .serverPhoto)
            }
        )

        do {
            _ = try await router.parse("recognized rows", preference: .serverPhoto)
            XCTFail("Expected server-photo parsing to require an image")
        } catch {
            XCTAssertFalse(serverCalled)
            XCTAssertFalse(photoCalled)
        }

        let result = try await router.parse("recognized rows", preference: .serverPhoto, image: UIImage())
        XCTAssertEqual(result.parser, .serverPhoto)
        XCTAssertTrue(photoCalled)
        XCTAssertFalse(serverCalled)
    }

    func testServerPhotoFallbackKeepsReturnedParserMetadataAfterReconciliation() async throws {
        let response = receipt(
            parser: .server,
            requestedParser: .serverPhoto,
            fallback: .server,
            warnings: ["Photo parsing unavailable; used text-only parsing."]
        )
        let router = ReceiptParserRouter(
            onDevice: { _ in XCTFail("device should not run"); return nil },
            server: { _ in XCTFail("text server should not run"); return nil },
            preparePhoto: { _ in self.preparedPhoto() },
            serverPhoto: { _, _ in response }
        )

        let result = try await router.parse("TACO 50.00", preference: .serverPhoto, image: UIImage())

        XCTAssertEqual(result.parser, .server)
        XCTAssertEqual(result.requestedParser, .serverPhoto)
        XCTAssertEqual(result.fallback, .server)
        XCTAssertTrue(result.warnings.contains("Photo parsing unavailable; used text-only parsing."))
    }

    func testServerPhotoAttemptStartsAfterPreparationAndImmediatelyBeforeUpload() async throws {
        var transitions: [String] = []
        let router = ReceiptParserRouter(
            onDevice: { _ in nil },
            server: { _ in nil },
            preparePhoto: { _ in
                transitions.append("prepared")
                return self.preparedPhoto()
            },
            serverPhoto: { _, _ in
                transitions.append("uploaded")
                return self.receipt(parser: .serverPhoto)
            },
            onAttempt: { parser in transitions.append("attempt:\(parser.rawValue)") }
        )

        _ = try await router.parse("TACO 50.00", preference: .serverPhoto, image: UIImage())

        XCTAssertEqual(transitions, ["prepared", "attempt:server_photo", "uploaded"])
    }

    func testServerPhotoPreparationFailureDoesNotPublishUploadAttempt() async {
        var attemptedParser: ReceiptParserKind?
        let router = ReceiptParserRouter(
            onDevice: { _ in nil },
            server: { _ in nil },
            preparePhoto: { _ in throw ReceiptPhotoUploadError.couldNotEncode },
            serverPhoto: { _, _ in
                XCTFail("upload must not start after preparation fails")
                return nil
            },
            onAttempt: { attemptedParser = $0 }
        )

        do {
            _ = try await router.parse("TACO 50.00", preference: .serverPhoto, image: UIImage())
            XCTFail("Expected preparation to fail")
        } catch {
            XCTAssertEqual(error as? ReceiptPhotoUploadError, .couldNotEncode)
        }
        XCTAssertNil(attemptedParser)
    }

    func testPhotoRecoveryPayloadIsTransientAndClearable() {
        let image = UIImage()
        var recovery = ReceiptPhotoRecovery()

        XCTAssertFalse(recovery.isAvailable)
        recovery.retain(image: image, ocrText: "private OCR")
        XCTAssertTrue(recovery.isAvailable)
        XCTAssertTrue(recovery.image === image)
        XCTAssertEqual(recovery.ocrText, "private OCR")

        recovery.clear()
        XCTAssertFalse(recovery.isAvailable)
        XCTAssertNil(recovery.image)
        XCTAssertNil(recovery.ocrText)
    }

    func testFailedPhotoUploadClearsInflightLegendButKeepsPreferenceAndRecovery() {
        let image = UIImage()
        var recovery = ReceiptPhotoRecovery()
        recovery.retain(image: image, ocrText: "private OCR")
        var routing = ReceiptScanRoutingState(
            preference: .serverPhoto,
            attempt: .serverPhoto
        )

        routing.clearPhotoAttemptAfterFailure()

        XCTAssertEqual(routing.preference, .serverPhoto)
        XCTAssertNil(routing.attempt)
        XCTAssertNil(ReceiptPrivacyLegend.attemptText(for: routing.attempt))
        XCTAssertTrue(recovery.isAvailable)
        XCTAssertTrue(recovery.image === image)
        XCTAssertEqual(recovery.ocrText, "private OCR")
    }

    func testPreferenceLabelsUseProductLanguage() {
        XCTAssertEqual(
            ReceiptParserPreference.allCases.map(\.displayName),
            ["Automatic", "On device", "On server", "On server + photo"]
        )
    }

    func testOnlyServerPhotoPreferenceIsExperimental() {
        XCTAssertFalse(ReceiptParserPreference.automatic.isExperimental)
        XCTAssertFalse(ReceiptParserPreference.onDevice.isExperimental)
        XCTAssertFalse(ReceiptParserPreference.server.isExperimental)
        XCTAssertTrue(ReceiptParserPreference.serverPhoto.isExperimental)
    }

    func testParserKindsDecodePhotoAndLegacyServerWireValues() throws {
        XCTAssertEqual(
            try JSONDecoder().decode(ReceiptParserKind.self, from: Data("\"server_photo\"".utf8)),
            .serverPhoto
        )
        XCTAssertEqual(
            try JSONDecoder().decode(ReceiptParserKind.self, from: Data("\"cloudflare\"".utf8)),
            .server
        )
    }

    func testPhotoFallbackMetadataDecodesAdditively() throws {
        let json = """
        {
          "parser": "server",
          "requestedParser": "server_photo",
          "fallback": "server",
          "merchant": null,
          "items": [],
          "taxCents": 0,
          "tipCents": 0,
          "totalCents": 0,
          "warnings": []
        }
        """

        let receipt = try JSONDecoder().decode(ScannedReceipt.self, from: Data(json.utf8))

        XCTAssertEqual(receipt.parser, .server)
        XCTAssertEqual(receipt.requestedParser, .serverPhoto)
        XCTAssertEqual(receipt.fallback, .server)
    }

    func testPrivacyLegendReflectsActualParserAttempt() {
        XCTAssertEqual(
            ReceiptPrivacyLegend.text(for: .onDevice),
            "Everything is read on your phone."
        )
        XCTAssertEqual(
            ReceiptPrivacyLegend.text(for: .server),
            "Your photo stays on your phone. Only the recognized text is sent for parsing."
        )
        XCTAssertEqual(
            ReceiptPrivacyLegend.text(for: .serverPhoto),
            "The receipt photo and recognized text are sent securely to the server for AI parsing. The server does not store the photo. If Save captures to Photos is enabled, a local copy is saved to your photo library. The AI provider does not use it to train its models."
        )
        XCTAssertNil(ReceiptPrivacyLegend.text(for: Optional<ReceiptParserKind>.none))
    }

    func testPrivacyLegendUsesExactInFlightPhotoAttemptCopy() {
        XCTAssertEqual(
            ReceiptPrivacyLegend.attemptText(for: .serverPhoto),
            "Sending the photo and recognized text to the server. The server does not store the photo. If Save captures to Photos is enabled, a local copy is saved to your photo library."
        )
    }

    func testPrivacyLegendAcknowledgesUploadedPhotoOnTextFallback() {
        XCTAssertEqual(
            ReceiptPrivacyLegend.text(
                for: .server,
                requestedParser: .serverPhoto,
                fallback: .server
            ),
            "The receipt photo and recognized text were sent to the server for parsing. The server used the recognized-text fallback and does not store the photo. If Save captures to Photos is enabled, a local copy is saved to your photo library."
        )
    }

    private func receipt(
        parser: ReceiptParserKind,
        requestedParser: ReceiptParserKind? = nil,
        fallback: ReceiptParserKind? = nil,
        items: [ScannedReceiptItem]? = nil,
        warnings: [String] = []
    ) -> ScannedReceipt {
        ScannedReceipt(
            parser: parser,
            requestedParser: requestedParser,
            fallback: fallback,
            merchant: nil,
            items: items ?? [
                ScannedReceiptItem(name: "TACO", quantity: 1, unitPriceCents: 5_000, verification: .verified)
            ],
            taxCents: 0,
            tipCents: 0,
            totalCents: 5_000,
            warnings: warnings
        )
    }

    private func preparedPhoto() -> PreparedReceiptPhoto {
        PreparedReceiptPhoto(
            jpegData: Data([0xff, 0xd8, 0xff, 0xd9]),
            pixelWidth: 10,
            pixelHeight: 10
        )
    }
}

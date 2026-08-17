import XCTest
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

    func testPreferenceLabelsUseProductLanguage() {
        XCTAssertEqual(
            ReceiptParserPreference.allCases.map(\.displayName),
            ["Automatic", "On device", "On server"]
        )
    }

    private func receipt(parser: ReceiptParserKind, items: [ScannedReceiptItem]? = nil) -> ScannedReceipt {
        ScannedReceipt(
            parser: parser,
            merchant: nil,
            items: items ?? [
                ScannedReceiptItem(name: "TACO", quantity: 1, unitPriceCents: 5_000, verification: .verified)
            ],
            taxCents: 0,
            tipCents: 0,
            totalCents: 5_000,
            warnings: []
        )
    }
}

import XCTest
@testable import Settlr

final class ReceiptEvidenceTests: XCTestCase {
    func testLeadingQuantityOwnsCountAndTrailingDigitsStayInName() {
        let modelReceipt = makeReceipt(items: [
            ScannedReceiptItem(name: "XX AMB", quantity: 23, unitPriceCents: 34_500, verification: .unverified)
        ])

        let reconciled = ReceiptReconciler.reconcile(modelReceipt, ocrText: "1   XX AMB 23   105.00")

        XCTAssertEqual(reconciled.items[0].name, "XX AMB 23")
        XCTAssertEqual(reconciled.items[0].quantity, 1)
        XCTAssertEqual(reconciled.items[0].unitPriceCents, 10_500)
        XCTAssertEqual(reconciled.items[0].verification, .verified)
    }

    func testRepeatedNamesConsumeDifferentPrintedRowsInOrder() {
        let modelReceipt = makeReceipt(items: [
            ScannedReceiptItem(name: "TACO", quantity: 1, unitPriceCents: 1, verification: .unverified),
            ScannedReceiptItem(name: "TACO", quantity: 1, unitPriceCents: 1, verification: .unverified),
        ])

        let reconciled = ReceiptReconciler.reconcile(modelReceipt, ocrText: "1 TACO 50.00\n1 TACO 70.00")

        XCTAssertEqual(reconciled.items.map(\.unitPriceCents), [5_000, 7_000])
        XCTAssertEqual(reconciled.items.map(\.verification), [.verified, .verified])
    }

    func testShortNameDoesNotFuzzyMatchLongerPrintedRow() {
        let modelReceipt = makeReceipt(items: [
            ScannedReceiptItem(name: "MOZ", quantity: 1, unitPriceCents: 12_300, verification: .unverified)
        ])

        let reconciled = ReceiptReconciler.reconcile(modelReceipt, ocrText: "1 MOZZARELLA 200.00")

        XCTAssertEqual(reconciled.items[0].unitPriceCents, 12_300)
        XCTAssertEqual(reconciled.items[0].verification, .unverified)
        XCTAssertTrue(reconciled.warnings.contains { $0.contains("couldn't be matched") })
    }

    func testPrintedQuantityBuildsExactUnitPrice() {
        let modelReceipt = makeReceipt(items: [
            ScannedReceiptItem(name: "MICHELADA", quantity: 1, unitPriceCents: 1, verification: .unverified)
        ])

        let reconciled = ReceiptReconciler.reconcile(modelReceipt, ocrText: "3x MICHELADA 70.50")

        XCTAssertEqual(reconciled.items[0].quantity, 3)
        XCTAssertEqual(reconciled.items[0].unitPriceCents, 2_350)
        XCTAssertEqual(reconciled.items[0].verification, .verified)
    }

    func testLegacyResponseDefaultsMetadataSafely() throws {
        let json = #"{"merchant":"Cafe","items":[{"name":"TACO","quantity":2,"unitPriceCents":5000}],"taxCents":0,"tipCents":0,"totalCents":10000,"warnings":[]}"#
        let receipt = try JSONDecoder().decode(ScannedReceipt.self, from: Data(json.utf8))

        XCTAssertEqual(receipt.parser, .server)
        XCTAssertEqual(receipt.items[0].verification, .unverified)
    }

    func testCurrentResponseDecodesParserAndVerificationMetadata() throws {
        let json = #"{"parser":"on_device","merchant":null,"items":[{"name":"TACO","quantity":1,"unitPriceCents":5000,"verification":"verified"}],"taxCents":0,"tipCents":0,"totalCents":5000,"warnings":[]}"#
        let receipt = try JSONDecoder().decode(ScannedReceipt.self, from: Data(json.utf8))

        XCTAssertEqual(receipt.parser, .onDevice)
        XCTAssertEqual(receipt.items[0].verification, .verified)
    }

    private func makeReceipt(items: [ScannedReceiptItem]) -> ScannedReceipt {
        ScannedReceipt(
            parser: .onDevice,
            merchant: nil,
            items: items,
            taxCents: 0,
            tipCents: 0,
            totalCents: 0,
            warnings: []
        )
    }
}

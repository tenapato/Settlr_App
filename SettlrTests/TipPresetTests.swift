import XCTest
@testable import Settlr

final class TipPresetTests: XCTestCase {
    func testTwelvePercentIsRenderedAndRecognizedUsingRoundedCents() {
        // This catches the chips and active-state detector using different
        // preset lists or truncating a fractional cent.
        XCTAssertEqual(TipPreset.values, [10, 12, 15, 20])
        XCTAssertEqual(TipPreset.cents(base: 10_005, percent: 12), 1_201)
        XCTAssertEqual(TipPreset.activePercent(base: 10_005, tipCents: 1_201), 12)
    }

    func testChangingFromTenToTwelvePercentReplacesTipInsideExplicitTotal() {
        // This catches percentage changes compounding the new tip on top of the
        // old one instead of removing the old tip from the selected total first.
        let base = 10_005
        let oldTip = 1_001
        let selectedTotalWithOldTip = 11_006
        let newTip = TipPreset.cents(base: base, percent: 12)

        XCTAssertEqual(
            TipPreset.retotal(
                selectedTotal: selectedTotalWithOldTip,
                replacing: oldTip,
                with: newTip
            ),
            11_206
        )
    }
}

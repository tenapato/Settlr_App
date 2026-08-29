import Foundation
import XCTest
@testable import Settlr

final class CardFortnightPresentationTests: XCTestCase {
    private func day(_ value: String) -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)!
    }

    func testExactRangeLabels() {
        XCTAssertEqual(FortnightNavigatorState.current(reference: day("2026-08-20")).label, "16–31 Aug")
        XCTAssertEqual(FortnightNavigatorState.previous(reference: day("2026-08-20")).label, "1–15 Aug")
        XCTAssertEqual(FortnightNavigatorState.next(reference: day("2026-08-20")).label, "1–15 Sep")
    }

    func testCrossMonthSelectionKeepsResolvedDueMonth() {
        XCTAssertEqual(FortnightNavigatorState.next(reference: day("2026-08-20")).monthKeys, ["2026-09"])
    }

    func testAllCardsIsExplicitMode() {
        let state = FortnightNavigatorState.all(reference: day("2026-08-20"))
        XCTAssertEqual(state.mode, .all)
        XCTAssertEqual(state.label, "All cards")
    }
}

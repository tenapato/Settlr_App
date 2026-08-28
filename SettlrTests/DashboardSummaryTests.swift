import Foundation
import XCTest
@testable import Settlr

final class DashboardSummaryTests: XCTestCase {
    func testAvailableSubtractsSavingsFromNet() throws {
        let data = Data(#"{"incomeCents":30000,"expenseCents":10000,"netCents":20000,"savingsNetCents":5000}"#.utf8)
        let summary = try JSONDecoder().decode(SummaryResponse.self, from: data)
        XCTAssertEqual(summary.availableCents, 15_000)
    }

    func testLegacySummaryDefaultsSavingsToZero() throws {
        let data = Data(#"{"netCents":20000}"#.utf8)
        XCTAssertEqual(try JSONDecoder().decode(SummaryResponse.self, from: data).availableCents, 20_000)
    }
}

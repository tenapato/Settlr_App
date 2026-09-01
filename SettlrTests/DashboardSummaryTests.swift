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

    func testMoneyFlowUsesCashDirectionForEverySummaryValue() throws {
        // This catches spending or savings deposits appearing as money coming
        // in when the Dashboard renders the approved vertical flow trace.
        let data = Data(#"{"incomeCents":2810000,"expenseCents":848000,"netCents":1962000,"savingsNetCents":120000}"#.utf8)
        let summary = try JSONDecoder().decode(SummaryResponse.self, from: data)

        let flow = DashboardMoneyFlowPresentation(summary: summary)

        XCTAssertEqual(flow.entries.map(\.kind), [.income, .spending, .savings])
        XCTAssertEqual(flow.entries.map(\.signedCents), [2_810_000, -848_000, -120_000])
    }

    func testSavingsWithdrawalFlowsBackIntoAvailableMoney() throws {
        let data = Data(#"{"incomeCents":0,"expenseCents":0,"netCents":0,"savingsNetCents":-75000}"#.utf8)
        let summary = try JSONDecoder().decode(SummaryResponse.self, from: data)

        let savings = DashboardMoneyFlowPresentation(summary: summary).entries[2]

        XCTAssertEqual(savings.kind, .savings)
        XCTAssertEqual(savings.signedCents, 75_000)
    }
}

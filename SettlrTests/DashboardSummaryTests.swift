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

    func testIncomeOnlyMonthBuildsAnimatedFactualSignals() throws {
        let data = Data(#"{"incomeCents":100000,"expenseCents":0,"netCents":100000,"savingsNetCents":0,"incomeCount":1,"expenseCount":0,"transactionCount":1}"#.utf8)
        let summary = try JSONDecoder().decode(SummaryResponse.self, from: data)

        let result = DashboardFallbackSignals.build(summary: summary)

        XCTAssertFalse(result.isQuiet)
        XCTAssertTrue(result.shouldAnimate)
        XCTAssertEqual(result.signals.map(\.kind), [.income, .available, .noSpending, .movementCount])
    }

    func testAllZeroMonthBuildsOneQuietSignal() throws {
        let summary = try JSONDecoder().decode(SummaryResponse.self, from: Data(#"{}"#.utf8))

        let result = DashboardFallbackSignals.build(summary: summary)

        XCTAssertTrue(result.isQuiet)
        XCTAssertFalse(result.shouldAnimate)
        XCTAssertEqual(result.signals.map(\.kind), [.noMovement])
    }

    func testSavingsUsesMoneyFlowSign() throws {
        let data = Data(#"{"savingsNetCents":75000}"#.utf8)
        let summary = try JSONDecoder().decode(SummaryResponse.self, from: data)

        XCTAssertEqual(
            DashboardFallbackSignals.build(summary: summary)
                .signals.first(where: { $0.kind == .savings })?.signedCents,
            -75_000
        )
    }

    func testNegativeAvailableKeepsItsSign() throws {
        let data = Data(#"{"netCents":-25000}"#.utf8)
        let summary = try JSONDecoder().decode(SummaryResponse.self, from: data)

        let available = DashboardFallbackSignals.build(summary: summary)
            .signals.first(where: { $0.kind == .available })

        XCTAssertEqual(available?.signedCents, -25_000)
    }

    func testPositiveSpendingWithoutCategoriesRemainsAFactualSignal() throws {
        let data = Data(#"{"expenseCents":42000,"netCents":-42000,"expenseCount":1,"transactionCount":1}"#.utf8)
        let summary = try JSONDecoder().decode(SummaryResponse.self, from: data)

        let result = DashboardFallbackSignals.build(summary: summary)

        XCTAssertEqual(result.signals.first?.kind, .spending)
        XCTAssertEqual(result.signals.first?.signedCents, -42_000)
        XCTAssertFalse(result.signals.contains(where: { $0.kind == .noSpending }))
    }

    func testFallbackSignalsAreCappedAtFiveFacts() throws {
        let data = Data(#"{"incomeCents":200000,"expenseCents":80000,"netCents":120000,"savingsNetCents":20000,"incomeCount":3,"expenseCount":4,"transactionCount":7}"#.utf8)
        let summary = try JSONDecoder().decode(SummaryResponse.self, from: data)

        let result = DashboardFallbackSignals.build(summary: summary)

        XCTAssertEqual(result.signals.count, 5)
        XCTAssertEqual(result.signals.map(\.kind), [.income, .spending, .available, .savings, .movementCount])
    }

    func testOneRealInsightUsesHeroWithoutTickerEntries() throws {
        let fallback = DashboardFallbackSignals.build(
            summary: try JSONDecoder().decode(SummaryResponse.self, from: Data(#"{}"#.utf8))
        )

        XCTAssertEqual(
            DashboardSignalSectionMode.resolve(realInsightCount: 1, fallback: fallback),
            .spending(primaryIndex: 0, tickerIndices: [])
        )
    }

    func testFiveRealInsightsUseHeroAndFourTickerEntries() throws {
        let fallback = DashboardFallbackSignals.build(
            summary: try JSONDecoder().decode(SummaryResponse.self, from: Data(#"{}"#.utf8))
        )

        XCTAssertEqual(
            DashboardSignalSectionMode.resolve(realInsightCount: 5, fallback: fallback),
            .spending(primaryIndex: 0, tickerIndices: [1, 2, 3, 4])
        )
    }

    func testColdLoadOwnsDashboardRootBeforeContentExists() {
        let state = DashboardRootPresentation.resolve(
            hasSummary: false,
            isLoading: true,
            hasError: false
        )

        XCTAssertEqual(state, .coldLoading)
    }

    func testInitialDashboardFrameUsesColdLoaderBeforeTaskStarts() {
        let state = DashboardRootPresentation.resolve(
            hasSummary: false,
            isLoading: false,
            hasError: false
        )

        XCTAssertEqual(state, .coldLoading)
    }

    func testRetryReplacesUncachedErrorWithLoadingFeedback() {
        let state = DashboardRootPresentation.resolve(
            hasSummary: false,
            isLoading: true,
            hasError: true
        )

        XCTAssertEqual(state, .coldLoading)
    }

    func testRefreshKeepsCachedDashboardContentVisible() {
        let state = DashboardRootPresentation.resolve(
            hasSummary: true,
            isLoading: true,
            hasError: false
        )

        XCTAssertEqual(state, .content)
    }
}

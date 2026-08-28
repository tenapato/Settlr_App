import XCTest
@testable import Settlr

final class ActivityEventTests: XCTestCase {
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    func testMixedFixturesSortNewestFirst() throws {
        let expense: Expense = try decode("""
        {"id":"e-1","description":"Coffee","amountCents":1200,"currency":"MXN","occurredAt":"2026-08-20T08:00:00Z","categoryId":null,"creditCardId":null,"paymentChannel":"cash","notes":null,"msiInstallment":null,"msiCount":null,"deferredInstallment":null,"deferredCount":null,"billSplitId":null}
        """)
        let income: Income = try decode("""
        {"id":"i-1","description":"Salary","amountCents":90000,"currency":"MXN","occurredAt":"2026-08-21T08:00:00Z","categoryId":null,"source":"Payroll","recurringSeriesId":null}
        """)
        let result = ActivityComposer.compose(expenses: [expense], income: [income], savings: [], splits: [])

        XCTAssertEqual(result.timeline.map(\.id), ["income:i-1", "expense:e-1"])
        XCTAssertEqual(result.timeline.map(\.amountCents), [90000, -1200])
    }

    func testCompletedSplitOwnedByExpenseIsNotDuplicated() throws {
        let expense: Expense = try decode("""
        {"id":"e-1","description":"Dinner","amountCents":30000,"currency":"MXN","occurredAt":"2026-08-20T20:00:00Z","categoryId":null,"creditCardId":null,"paymentChannel":"cash","notes":null,"msiInstallment":null,"msiCount":null,"deferredInstallment":null,"deferredCount":null,"billSplitId":"split-1"}
        """)
        let split: BillSplitSummary = try decode("""
        {"id":"split-1","shareToken":"token","shareUrl":null,"merchant":"Dinner","currency":"MXN","occurredAt":"2026-08-20T20:00:00Z","totalCents":30000,"status":"settled","payer":"organizer_paid","participantCount":2,"settledCount":2,"pendingCount":0,"outstandingCents":0}
        """)

        let result = ActivityComposer.compose(expenses: [expense], income: [], savings: [], splits: [split])

        XCTAssertEqual(result.timeline.count, 1)
        XCTAssertEqual(result.timeline.first?.id, "expense:e-1")
        XCTAssertTrue(result.timeline.first?.context.contains("Split") == true)
        XCTAssertTrue(result.attention.isEmpty)
    }

    func testOpenSplitsBecomeAttentionInsteadOfTimelineEvents() throws {
        let split: BillSplitSummary = try decode("""
        {"id":"split-1","shareToken":"token","shareUrl":null,"merchant":"Dinner","currency":"MXN","occurredAt":"2026-08-20T20:00:00Z","totalCents":30000,"status":"open","payer":"organizer_paid","participantCount":2,"settledCount":0,"pendingCount":2,"outstandingCents":null}
        """)

        let result = ActivityComposer.compose(expenses: [], income: [], savings: [], splits: [split])

        XCTAssertTrue(result.timeline.isEmpty)
        XCTAssertEqual(result.attention.map(\.id), ["split-1"])
    }

    func testSplitExpenseKeepsActualPaymentSourceAndCardID() throws {
        let expense: Expense = try decode("""
        {"id":"e-card","description":"Hotel","amountCents":45000,"currency":"MXN","occurredAt":"2026-08-20T20:00:00Z","categoryId":null,"creditCardId":"card-9","paymentChannel":"credit_card","notes":null,"msiInstallment":null,"msiCount":null,"deferredInstallment":null,"deferredCount":null,"billSplitId":"split-9"}
        """)
        let split: BillSplitSummary = try decode("""
        {"id":"split-9","shareToken":"token","shareUrl":null,"merchant":"Hotel","currency":"MXN","occurredAt":"2026-08-20T20:00:00Z","totalCents":45000,"status":"settled","payer":"organizer_paid","participantCount":2,"settledCount":2,"pendingCount":0,"outstandingCents":0}
        """)

        let event = try XCTUnwrap(ActivityComposer.compose(expenses: [expense], income: [], savings: [], splits: [split]).timeline.first)

        XCTAssertEqual(event.context, "Card · Split")
        XCTAssertEqual(event.paymentSource, "card-9")
    }

    private func decode<T: Decodable>(_ json: String) throws -> T {
        try decoder.decode(T.self, from: Data(json.utf8))
    }
}

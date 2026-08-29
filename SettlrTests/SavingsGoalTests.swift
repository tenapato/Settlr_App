import Foundation
import XCTest

final class SavingsGoalTests: XCTestCase {
    func testTargetAccountDecodesServerProgress() throws {
        let account = try decodeAccount(#"{"id":"a","name":"Trip","currency":"MXN","color":null,"sortOrder":0,"balanceCents":2500,"targetAmountCents":10000,"targetDate":"2027-01-01","goalStatus":"in_progress","progressPct":25,"remainingCents":7500}"#)
        XCTAssertEqual(account.targetAmountCents, 10_000)
        XCTAssertEqual(account.targetDate, "2027-01-01")
        XCTAssertEqual(account.goalStatus, "in_progress")
        XCTAssertEqual(account.progressPct, 25.0)
        XCTAssertEqual(account.remainingCents, 7_500)
    }

    func testFlexibleAccountKeepsGoalFieldsNil() throws {
        let account = try decodeAccount(#"{"id":"a","name":"Flexible","currency":"MXN","color":null,"sortOrder":0,"balanceCents":2500}"#)
        XCTAssertNil(account.targetAmountCents)
        XCTAssertNil(account.targetDate)
        XCTAssertNil(account.goalStatus)
        XCTAssertNil(account.progressPct)
        XCTAssertNil(account.remainingCents)
    }

    func testCreateGoalBodyIncludesOptionalTargetFields() throws {
        let body = CreateSavingsAccountBody(
            name: "Trip",
            color: "#22c55e",
            currency: "MXN",
            targetAmountCents: 10_000,
            targetDate: "2027-01-01"
        )
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(body)) as? [String: Any]
        XCTAssertEqual(json?["targetAmountCents"] as? Int, 10_000)
        XCTAssertEqual(json?["targetDate"] as? String, "2027-01-01")
    }

    func testPatchGoalBodySendsNullWhenClearingGoal() throws {
        let body = UpdateSavingsAccountBody(name: "Flexible", color: "#22c55e")
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(body)) as? [String: Any]
        XCTAssertTrue(json?.keys.contains("targetAmountCents") == true)
        XCTAssertTrue(json?.keys.contains("targetDate") == true)
        XCTAssertTrue(json?["targetAmountCents"] is NSNull)
        XCTAssertTrue(json?["targetDate"] is NSNull)
    }

    func testBlankTargetAmountClearsGoal() {
        XCTAssertNil(try? parseSavingsTargetAmount(""))
        XCTAssertNil(try? parseSavingsTargetAmount("   "))
    }

    func testInvalidTargetAmountsDoNotBecomeCents() {
        for raw in ["0", "-1", "nan", "infinity", "1e309", "999999999999999999999999999"] {
            XCTAssertThrowsError(try parseSavingsTargetAmount(raw))
        }
    }

    func testTargetAmountParsesToCents() throws {
        XCTAssertEqual(try parseSavingsTargetAmount("100.25"), 10_025)
    }

    private func decodeAccount(_ json: String) throws -> SavingsAccount {
        try JSONDecoder().decode(SavingsAccount.self, from: Data(json.utf8))
    }
}

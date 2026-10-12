import XCTest
@testable import Settlr

final class FeatureAccessTests: XCTestCase {
    private func user(disabled: [String]) -> MeUser {
        MeUser(
            id: "user",
            name: "User",
            email: "user@example.com",
            emailVerified: true,
            role: "user",
            disabledFeatures: disabled
        )
    }

    func testSignalTabsRespectFeatures() {
        XCTAssertEqual(Tab.available(for: user(disabled: [])), [.home, .activity, .savings, .cards])
        XCTAssertEqual(
            Tab.available(for: user(disabled: ["expenses", "income", "bill_splits", "savings", "credit_cards"])),
            [.home]
        )
        XCTAssertFalse(Tab.activity.isAvailable(for: user(disabled: ["expenses", "income", "bill_splits"])))
        XCTAssertFalse(Tab.cards.isAvailable(for: user(disabled: ["credit_cards"])))
    }
}

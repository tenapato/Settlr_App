import SwiftUI
import XCTest
@testable import Settlr

final class AppearancePreferenceTests: XCTestCase {
    func testColorSchemeMapping() {
        XCTAssertEqual(SettlrAppearance.dark.colorScheme, .dark)
        XCTAssertEqual(SettlrAppearance.light.colorScheme, .light)
        XCTAssertNil(SettlrAppearance.system.colorScheme)
    }

    func testDefaultRawValueIsDark() {
        XCTAssertEqual(SettlrAppearance(rawValue: "unknown") ?? .dark, .dark)
    }
}

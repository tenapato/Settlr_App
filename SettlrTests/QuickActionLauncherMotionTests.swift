import XCTest
@testable import Settlr

final class QuickActionLauncherMotionTests: XCTestCase {
    func testOpenStateRotatesPlusIntoCloseMark() {
        let motion = QuickActionLauncherMotion(isOpen: true, isPressed: false, reduceMotion: false)

        XCTAssertEqual(motion.symbolName, "plus")
        XCTAssertEqual(motion.rotationDegrees, 45)
        XCTAssertEqual(motion.scale, 1)
    }

    func testPressCompressesLauncher() {
        let motion = QuickActionLauncherMotion(isOpen: false, isPressed: true, reduceMotion: false)

        XCTAssertEqual(motion.scale, 0.94)
    }

    func testReduceMotionRemovesSpatialMotion() {
        let motion = QuickActionLauncherMotion(isOpen: true, isPressed: true, reduceMotion: true)

        XCTAssertEqual(motion.symbolName, "xmark")
        XCTAssertEqual(motion.rotationDegrees, 0)
        XCTAssertEqual(motion.scale, 1)
    }
}

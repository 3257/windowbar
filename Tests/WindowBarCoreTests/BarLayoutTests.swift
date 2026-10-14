import XCTest

@testable import WindowBarCore

final class BarLayoutTests: XCTestCase {
    func testEmptyLayout() {
        let layout = BarLayout(availableWidth: 1000, focused: [])
        XCTAssertTrue(layout.buttons.isEmpty)
        XCTAssertEqual(layout.documentWidth, 1000)
    }

    func testManyWindowsFitOneRowAndFocusedWindowIsWider() {
        let layout = BarLayout(availableWidth: 1400, focused: (0..<14).map { $0 == 5 })
        XCTAssertEqual(layout.buttons.count, 14)
        XCTAssertLessThanOrEqual(layout.documentWidth, 1400.001)
        XCTAssertEqual(layout.buttons[5].width / layout.buttons[0].width, 1.3, accuracy: 0.001)
        XCTAssertLessThan(layout.buttons[0].width, 155)
    }

    func testExtremeWindowCountKeepsUsableTargetsAndScrolls() {
        let layout = BarLayout(availableWidth: 300, focused: Array(repeating: false, count: 100))
        XCTAssertGreaterThan(layout.documentWidth, 300)
        XCTAssertTrue(layout.buttons.allSatisfy { $0.width >= BarLayout.minimumButtonWidth })
        XCTAssertTrue(zip(layout.buttons, layout.buttons.dropFirst()).allSatisfy { $0.x + $0.width < $1.x })
    }

    func testMultipleFocusFlagsDoNotOverrunTheAllocatedWidth() {
        let layout = BarLayout(availableWidth: 700, focused: [true, false, true, false])
        XCTAssertEqual(layout.documentWidth, 700, accuracy: 0.001)
    }

    func testNegativeAvailableSpaceNeverProducesNegativeGeometry() {
        let layout = BarLayout(availableWidth: -100, focused: [false])
        XCTAssertEqual(layout.buttons.first?.width, 42)
        XCTAssertEqual(layout.documentWidth, 42)
    }
}

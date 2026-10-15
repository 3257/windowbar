import XCTest

@testable import WindowBarCore

final class AppCommandTests: XCTestCase {
    func testSettingsHelperHasAnExplicitIsolatedCommand() throws {
        XCTAssertEqual(try AppCommand.parse(["--settings"]), .settings)
        XCTAssertThrowsError(try AppCommand.parse(["--settings", "extra"]))
    }
    func testIsolatedChecksAndExplicitInstallationCommands() throws {
        XCTAssertEqual(try AppCommand.parse(["--self-test"]), .selfTest)
        XCTAssertEqual(try AppCommand.parse(["--install"]), .install)
        XCTAssertThrowsError(try AppCommand.parse(["--install", "unexpected"]))
    }
    func testNormalAndScreenshotCommands() throws {
        XCTAssertEqual(try AppCommand.parse([]), .run(demo: false, screenshots: false))
        XCTAssertEqual(try AppCommand.parse(["--screenshot-demo"]), .run(demo: true, screenshots: true))
    }

    func testInvalidDeveloperCommandsDoNotAccidentallyLaunchTheBar() {
        XCTAssertThrowsError(try AppCommand.parse(["--render-preview"]))
        XCTAssertThrowsError(try AppCommand.parse(["--dock-guard", "-1", "token"]))
        XCTAssertThrowsError(try AppCommand.parse(["--unknown"]))
    }

    func testGuardCommandAndPreviewPathWithSpaces() throws {
        XCTAssertEqual(
            try AppCommand.parse(["--dock-guard", "12", "token"]), .guardDock(pid: 12, token: "token"))
        XCTAssertEqual(
            try AppCommand.parse(["--render-preview", "sample view.png"]), .preview(path: "sample view.png"))
    }
}

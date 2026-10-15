import CoreGraphics
import XCTest

@testable import WindowBarCore

final class FeatureTests: XCTestCase {
    func testWindowOrderSurvivesDiscoveryChangesAndDropsClosedWindows() {
        var order = WindowOrdering()
        order.reconcile(["a", "b", "c"])
        order.move("c", before: "a")
        order.reconcile(["b", "a", "c", "d", "d"])
        XCTAssertEqual(order.identifiers, ["c", "a", "b", "d"])
        order.reconcile(["d", "a", "c"])
        XCTAssertEqual(order.identifiers, ["c", "a", "d"])
    }

    func testMoveIgnoresStaleTargetsAndSupportsBothDirections() {
        var order = WindowOrdering()
        order.reconcile(["a", "b", "c"])
        order.move("a", before: "c")
        XCTAssertEqual(order.identifiers, ["b", "a", "c"])
        order.move("c", before: "b")
        order.move("missing", before: "a")
        order.move("a", before: "missing")
        order.move("a", before: "a")
        XCTAssertEqual(order.identifiers, ["c", "b", "a"])
        order.move("c", relativeTo: "a", after: true)
        XCTAssertEqual(order.identifiers, ["b", "a", "c"])
    }

    func testLargestIntersectionAssignsSpanningWindowToOneDisplay() {
        let displays = [
            DisplayRegion(id: 1, frame: CGRect(x: -1000, y: 0, width: 1000, height: 900)),
            DisplayRegion(id: 2, frame: CGRect(x: 0, y: 0, width: 1200, height: 900)),
        ]
        XCTAssertEqual(
            DisplayFilter.displayID(for: CGRect(x: -100, y: 50, width: 600, height: 500), displays: displays),
            2)
        XCTAssertEqual(
            DisplayFilter.displayID(for: CGRect(x: -900, y: 50, width: 400, height: 500), displays: displays),
            1)
        XCTAssertNil(DisplayFilter.displayID(for: nil, displays: displays))
        XCTAssertNil(
            DisplayFilter.displayID(for: CGRect(x: 5000, y: 0, width: 50, height: 50), displays: displays))
    }

    func testDisplayTieIsDeterministicAndCoordinatesHandleTopAndLeftDisplays() {
        let displays = [
            DisplayRegion(id: 9, frame: CGRect(x: 0, y: 0, width: 100, height: 100)),
            DisplayRegion(id: 4, frame: CGRect(x: 100, y: 0, width: 100, height: 100)),
        ]
        XCTAssertEqual(
            DisplayFilter.displayID(for: CGRect(x: 90, y: 10, width: 20, height: 20), displays: displays), 9)
        XCTAssertEqual(
            DisplayFilter.cocoaFrame(
                accessibilityFrame: CGRect(x: -800, y: -600, width: 300, height: 400), primaryDisplayTop: 1000
            ),
            CGRect(x: -800, y: 1200, width: 300, height: 400))
    }

    func testCaptureRejectsAmbiguousWindowsAndDifferentProcesses() {
        let frame = CGRect(x: 10, y: 20, width: 100, height: 200)
        let candidates = [
            CaptureWindow(id: 1, pid: 42, frame: frame, title: "One"),
            CaptureWindow(id: 2, pid: 42, frame: frame, title: "Two"),
            CaptureWindow(id: 3, pid: 50, frame: frame, title: "One"),
        ]
        XCTAssertEqual(
            WindowCaptureMatcher.match(pid: 42, frame: frame, title: "Two", candidates: candidates), 2)
        XCTAssertNil(
            WindowCaptureMatcher.match(pid: 42, frame: frame, title: "Unknown", candidates: candidates))
        XCTAssertNil(WindowCaptureMatcher.match(pid: 99, frame: frame, title: "One", candidates: candidates))
        XCTAssertNil(WindowCaptureMatcher.match(pid: 42, frame: nil, title: "One", candidates: candidates))
    }

    func testCaptureMatchesUniqueGeometryWhenTitlesAreUnavailable() {
        let frame = CGRect(x: 10, y: 20, width: 100, height: 200)
        let candidate = CaptureWindow(id: 1, pid: 42, frame: frame.offsetBy(dx: 1, dy: 1), title: nil)
        XCTAssertEqual(
            WindowCaptureMatcher.match(pid: 42, frame: frame, title: "One", candidates: [candidate]), 1)
        XCTAssertNil(
            WindowCaptureMatcher.match(
                pid: 42, frame: frame.offsetBy(dx: 10, dy: 0), title: "One", candidates: [candidate]))
    }

    func testDefaultShortcutsAreDistinctAndTypingKeysAreRejected() throws {
        XCTAssertNoThrow(try ShortcutBinding.validate(ShortcutBinding.defaults))
        XCTAssertThrowsError(
            try ShortcutBinding.validate([ShortcutBinding(action: .nextWindow, keyCode: 0, modifiers: 0)]))
        XCTAssertThrowsError(
            try ShortcutBinding.validate([
                ShortcutBinding(action: .nextWindow, keyCode: 0, modifiers: ShortcutBinding.shift)
            ]))
        XCTAssertThrowsError(
            try ShortcutBinding.validate([
                ShortcutBinding(action: .nextWindow, keyCode: 55, modifiers: ShortcutBinding.command)
            ]))
        XCTAssertThrowsError(
            try ShortcutBinding.validate([ShortcutBinding.defaults[0], ShortcutBinding.defaults[0]]))
        var duplicateKey = ShortcutBinding.defaults[0]
        duplicateKey.action = .pinned1
        XCTAssertThrowsError(try ShortcutBinding.validate([ShortcutBinding.defaults[0], duplicateKey]))
    }

    func testKeyboardCyclingWrapsAndHandlesEmptyAndUnfocusedLists() {
        XCTAssertNil(ShortcutBinding.cycleIndex(count: 0, focusedIndex: nil, forward: true))
        XCTAssertEqual(ShortcutBinding.cycleIndex(count: 3, focusedIndex: 2, forward: true), 0)
        XCTAssertEqual(ShortcutBinding.cycleIndex(count: 3, focusedIndex: 0, forward: false), 2)
        XCTAssertEqual(ShortcutBinding.cycleIndex(count: 3, focusedIndex: nil, forward: false), 2)
        XCTAssertEqual(ShortcutAction.pinned9.pinnedIndex, 8)
        XCTAssertNil(ShortcutAction.nextWindow.pinnedIndex)
    }

    func testPreferencesMigrateAndPreserveEmptyPins() throws {
        let old = try JSONDecoder().decode(BarPreferences.self, from: Data("{}".utf8))
        XCTAssertNil(old.pinnedPaths)
        XCTAssertFalse(old.shortcutsEnabled)
        XCTAssertEqual(old.previewMode, .titles)
        var updated = old
        updated.pinnedPaths = []
        updated.previewMode = .thumbnails
        updated.windowScope = .currentDisplay
        XCTAssertEqual(
            try JSONDecoder().decode(BarPreferences.self, from: JSONEncoder().encode(updated)), updated)
    }

    func testProfileMatchesOnlyExactControlsAndRefusesDuplicateNames() {
        let profiles = [
            ChromeProfile(directory: "Default", name: "Personal"),
            ChromeProfile(directory: "Profile 1", name: "Work"),
        ]
        XCTAssertEqual(
            ProfileBadgeMatcher.match(controlText: "Profile: Work", profiles: profiles)?.directory,
            "Profile 1")
        XCTAssertNil(ProfileBadgeMatcher.match(controlText: "A page about Work", profiles: profiles))
        XCTAssertEqual(
            ProfileBadgeMatcher.match(controlText: "Ada (Work)", profiles: profiles)?.directory, "Profile 1")
        XCTAssertEqual(
            ProfileBadgeMatcher.matchMenuItem("Work (ada@example.test)", profiles: profiles)?.directory,
            "Profile 1")
        XCTAssertNil(ProfileBadgeMatcher.matchMenuItem("Some Work page", profiles: profiles))
        XCTAssertNil(
            ProfileBadgeMatcher.match(
                controlText: "Profile: Work",
                profiles: profiles + [ChromeProfile(directory: "Profile 2", name: "Work")]))
        XCTAssertEqual(
            ProfileBadgeMatcher.colorIndex(directory: "Profile 1"),
            ProfileBadgeMatcher.colorIndex(directory: "Profile 1"))
        XCTAssertEqual(ProfileBadgeMatcher.colorIndex(directory: "Profile 1", count: 0), 0)
    }
}

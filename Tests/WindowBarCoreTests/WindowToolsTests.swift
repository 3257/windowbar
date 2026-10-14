import XCTest

@testable import WindowBarCore

final class WindowToolsTests: XCTestCase {
    private let windows = [
        SearchableWindow(id: "one", title: "Café dashboard", app: "Google Chrome", profile: "Work"),
        SearchableWindow(
            id: "two", title: "Dashboard", app: "Google Chrome", profile: "Personal", minimized: true),
        SearchableWindow(id: "three", title: "build logs", app: "Terminal"),
    ]

    func testSearchMatchesTitleAppProfileAndMultipleTermsIgnoringCaseAndAccents() {
        XCTAssertEqual(
            WindowSearch.filter(windows, query: "CAFE chrome WORK", includeMinimized: true), ["one"])
        XCTAssertEqual(WindowSearch.filter(windows, query: "terminal", includeMinimized: true), ["three"])
        XCTAssertEqual(WindowSearch.filter(windows, query: "personal", includeMinimized: true), ["two"])
        XCTAssertEqual(WindowSearch.filter(windows, query: "work terminal", includeMinimized: true), [])
    }

    func testSearchEmptyWhitespaceAndMinimizedOptionPreserveOrder() {
        XCTAssertEqual(
            WindowSearch.filter(windows, query: " \n\t ", includeMinimized: true), ["one", "two", "three"])
        XCTAssertEqual(WindowSearch.filter(windows, query: "", includeMinimized: false), ["one", "three"])
        XCTAssertEqual(WindowSearch.filter(windows, query: "personal", includeMinimized: false), [])
    }

    func testGroupingByAppPreservesFirstSeenGroupsAndWindowOrder() {
        let entries = [
            GroupingWindow(
                id: "a", appKey: "chrome", appName: "Chrome", profileKey: "1", profileName: "Work"),
            GroupingWindow(id: "b", appKey: "terminal", appName: "Terminal"),
            GroupingWindow(
                id: "c", appKey: "chrome", appName: "Chrome", profileKey: "2", profileName: "Work"),
        ]
        let groups = WindowGrouping.groups(entries, mode: .app)
        XCTAssertEqual(groups.map(\.title), ["Chrome", "Terminal"])
        XCTAssertEqual(groups.map(\.windowIDs), [["a", "c"], ["b"]])
        XCTAssertEqual(WindowGrouping.groups(entries, mode: .none), [])
    }

    func testProfileGroupingUsesDirectoriesInsteadOfDuplicateNamesAndRetainsUnknownProfiles() {
        let entries = [
            GroupingWindow(
                id: "a", appKey: "chrome", appName: "Chrome", profileKey: "1", profileName: "Work"),
            GroupingWindow(
                id: "b", appKey: "chrome", appName: "Chrome", profileKey: "2", profileName: "Work"),
            GroupingWindow(id: "c", appKey: "chrome", appName: "Chrome"),
        ]
        let groups = WindowGrouping.groups(entries, mode: .appAndProfile)
        XCTAssertEqual(groups.count, 3)
        XCTAssertEqual(Set(groups.map(\.key)).count, 3)
        XCTAssertEqual(groups.flatMap(\.windowIDs), ["a", "b", "c"])
        XCTAssertEqual(WindowGrouping.groups([], mode: .app), [])
    }

    func testAutoHideWaitsForDelayAndRevealsImmediatelyAtEdge() {
        var state = AutoHideState()
        XCTAssertFalse(
            state.update(
                enabled: true, pointerInside: false, atEdge: false, interaction: false, now: 10, delay: 0.8))
        XCTAssertFalse(
            state.update(
                enabled: true, pointerInside: false, atEdge: false, interaction: false, now: 10.7, delay: 0.8)
        )
        XCTAssertTrue(
            state.update(
                enabled: true, pointerInside: false, atEdge: false, interaction: false, now: 11, delay: 0.8))
        XCTAssertFalse(
            state.update(
                enabled: true, pointerInside: false, atEdge: true, interaction: false, now: 11.1, delay: 0.8))
    }

    func testAutoHideInteractionPointerAndDisableCancelPendingHide() {
        var state = AutoHideState()
        _ = state.update(
            enabled: true, pointerInside: false, atEdge: false, interaction: false, now: 0, delay: 1)
        XCTAssertFalse(
            state.update(
                enabled: true, pointerInside: false, atEdge: false, interaction: true, now: 2, delay: 1))
        _ = state.update(
            enabled: true, pointerInside: false, atEdge: false, interaction: false, now: 3, delay: 1)
        XCTAssertFalse(
            state.update(
                enabled: true, pointerInside: true, atEdge: false, interaction: false, now: 5, delay: 1))
        _ = state.update(
            enabled: true, pointerInside: false, atEdge: false, interaction: false, now: 6, delay: 1)
        XCTAssertTrue(
            state.update(
                enabled: true, pointerInside: false, atEdge: false, interaction: false, now: 7, delay: 1))
        XCTAssertFalse(
            state.update(
                enabled: false, pointerInside: false, atEdge: false, interaction: false, now: 8, delay: 1))
    }

    func testEveryNewSettingRoundTripsAndOldPreferencesMigrateSafely() throws {
        let old = try JSONDecoder().decode(BarPreferences.self, from: Data("{}".utf8))
        XCTAssertTrue(old.searchEnabled)
        XCTAssertTrue(old.searchIncludesMinimized)
        XCTAssertTrue(old.hoverActionsEnabled)
        XCTAssertEqual(old.groupingMode, .none)
        XCTAssertFalse(old.autoHideEnabled)
        var changed = old
        changed.searchEnabled = false
        changed.searchIncludesMinimized = false
        changed.hoverActionsEnabled = false
        changed.groupingMode = .appAndProfile
        changed.autoHideEnabled = true
        changed.autoHideDelay = 1.5
        XCTAssertEqual(
            try JSONDecoder().decode(BarPreferences.self, from: JSONEncoder().encode(changed)), changed)
    }

    func testSearchShortcutMigrationPreservesCustomBindingsAndDoesNotClaimConflict() throws {
        var oldBindings = ShortcutBinding.defaults.filter { $0.action != .searchWindows }
        oldBindings[0].keyCode = 49
        let data = try JSONSerialization.data(withJSONObject: [
            "shortcuts": try JSONSerialization.jsonObject(with: JSONEncoder().encode(oldBindings))
        ])
        let migrated = try JSONDecoder().decode(BarPreferences.self, from: data)
        XCTAssertEqual(migrated.shortcuts, oldBindings)
        var preferences = BarPreferences()
        preferences.shortcutsEnabled = true
        XCTAssertTrue(preferences.activeShortcuts.contains { $0.action == .searchWindows })
        preferences.searchEnabled = false
        XCTAssertFalse(preferences.activeShortcuts.contains { $0.action == .searchWindows })
        XCTAssertTrue(preferences.activeShortcuts.contains { $0.action == .pinned1 })
        preferences.shortcutsEnabled = false
        XCTAssertTrue(preferences.activeShortcuts.isEmpty)
    }

    func testAutoHideDelayMigrationClampsCorruptOrOutOfRangeValues() throws {
        for (value, expected) in [(0.0, 0.2), (100.0, 3.0)] {
            let data = try JSONSerialization.data(withJSONObject: ["autoHideDelay": value])
            XCTAssertEqual(try JSONDecoder().decode(BarPreferences.self, from: data).autoHideDelay, expected)
        }
        for value in [Double.nan, Double.infinity, 0, 10] {
            var preferences = BarPreferences()
            preferences.autoHideDelay = value
            XCTAssertThrowsError(try preferences.validate())
        }
    }
}

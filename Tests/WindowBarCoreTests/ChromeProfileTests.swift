import XCTest

@testable import WindowBarCore

final class ChromeProfileTests: XCTestCase {
    func testAllProfilesAreListedWithDisplayNamesAndLastUsedFlag() throws {
        let data = Data(
            #"{"profile":{"last_used":"Profile 2","info_cache":{"Default":{"name":"Personal"},"Profile 1":{"name":"Work"},"Profile 2":{"name":"Development"},"Profile 3":{"name":"Client"}}}}"#
                .utf8)
        let profiles = try ChromeProfile.decodeLocalState(data)
        XCTAssertEqual(profiles.count, 4)
        XCTAssertEqual(profiles.map(\.name), ["Client", "Development", "Personal", "Work"])
        XCTAssertEqual(profiles.filter(\.lastUsed).map(\.directory), ["Profile 2"])
    }

    func testHiddenAndInvalidProfileDirectoriesAreExcluded() throws {
        let data = Data(
            #"{"profile":{"info_cache":{"../other":{"name":"Bad"},"System Profile":{"name":"System"},"Profile 1":{"name":"Hidden","is_omitted":true},"Profile 2":{"name":"Temporary","is_ephemeral":true},"Default":{"name":"Personal"}}}}"#
                .utf8)
        XCTAssertEqual(try ChromeProfile.decodeLocalState(data).map(\.directory), ["Default"])
    }

    func testMissingNameFallsBackToDirectoryAndDuplicateNamesKeepBothProfiles() throws {
        let data = Data(
            #"{"profile":{"info_cache":{"Default":{},"Profile 1":{"name":"Work"},"Profile 2":{"name":"Work"}}}}"#
                .utf8)
        let profiles = try ChromeProfile.decodeLocalState(data)
        XCTAssertEqual(profiles.count, 3)
        XCTAssertEqual(profiles.first?.name, "Default")
        XCTAssertEqual(profiles.filter { $0.name == "Work" }.count, 2)
    }

    func testMalformedStateIsReportedAndAbsentCacheIsEmpty() throws {
        XCTAssertThrowsError(try ChromeProfile.decodeLocalState(Data("broken".utf8)))
        XCTAssertTrue(try ChromeProfile.decodeLocalState(Data("{}".utf8)).isEmpty)
    }

    func testLaunchArgumentsDoNotSplitAProfileDirectoryContainingSpaces() {
        let profile = ChromeProfile(directory: "Profile 2", name: "Work")
        XCTAssertEqual(profile.launchArguments.first, "--profile-directory=Profile 2")
        XCTAssertTrue(profile.launchArguments.contains("--ignore-profile-directory-if-not-exists"))
        XCTAssertEqual(profile.launchArguments.last, "about:blank")
    }
}

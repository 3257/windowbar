import XCTest

@testable import WindowBarCore

final class StateTests: XCTestCase {
    func testSelectionInvalidatesAnInFlightScan() {
        var generation = ScanGeneration()
        let captured = generation.value
        generation.invalidate()
        XCTAssertFalse(generation.accepts(captured))
        XCTAssertTrue(generation.accepts(generation.value))
    }

    func testDockBackupPreservesAbsentPreferences() throws {
        let snapshot = DockSnapshot(token: "test", ownerPID: 123, autohide: nil, delay: nil)
        let data = try PropertyListEncoder().encode(snapshot)
        XCTAssertEqual(try PropertyListDecoder().decode(DockSnapshot.self, from: data), snapshot)
        let dictionary = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        XCTAssertNil(dictionary["autohide"])
        XCTAssertNil(dictionary["autohide-delay"])
    }

    func testDockBackupPreservesExistingFalseAndZero() throws {
        let snapshot = DockSnapshot(token: "test", ownerPID: 123, autohide: false, delay: 0)
        let data = try PropertyListEncoder().encode(snapshot)
        XCTAssertEqual(try PropertyListDecoder().decode(DockSnapshot.self, from: data), snapshot)
    }

    func testBackupIsCompatibleWithPrototypeKeys() throws {
        let legacy: [String: Any] = ["token": "legacy", "pid": 77, "autohide": true, "autohide-delay": 3.5]
        let data = try PropertyListSerialization.data(fromPropertyList: legacy, format: .xml, options: 0)
        let snapshot = try PropertyListDecoder().decode(DockSnapshot.self, from: data)
        XCTAssertEqual(snapshot.ownerPID, 77)
        XCTAssertEqual(snapshot.delay, 3.5)
    }
}

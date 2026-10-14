import CoreFoundation
import Darwin
import Foundation
import OSLog
import WindowBarCore

protocol DockReplacing {
    var isEnabled: Bool { get }
    @discardableResult func enable() -> Bool
    @discardableResult func restore() -> Bool
}

/// Serializes preference changes across the app and its crash guard.
final class DockController: DockReplacing {
    static let backupURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/WindowBar/dock-backup.plist")
    private static let logger = Logger(subsystem: "local.windowbar.app", category: "Dock")
    private var token: String?

    var isEnabled: Bool { token != nil }

    private static func readBackup() throws -> DockSnapshot? {
        guard FileManager.default.fileExists(atPath: backupURL.path) else { return nil }
        return try PropertyListDecoder().decode(DockSnapshot.self, from: Data(contentsOf: backupURL))
    }

    @discardableResult private static func run(_ path: String, _ arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            logger.error("Could not run Dock command: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    private static func transactionLock() throws -> InstanceLock {
        try InstanceLock(directory: backupURL.deletingLastPathComponent(), name: "dock.lock", waits: true)
    }

    private static func alive(_ pid: Int32) -> Bool {
        pid > 0 && (kill(pid, 0) == 0 || errno == EPERM)
    }

    /// Call under dock.lock. Retain the backup if any preference write fails.
    private static func restoreUnlocked(_ backup: DockSnapshot) throws -> Bool {
        guard try readBackup()?.token == backup.token else { return false }
        var succeeded = true
        for key in ["autohide", "autohide-delay"] {
            let arguments: [String]?
            if key == "autohide", let value = backup.autohide {
                arguments = ["write", "com.apple.dock", key, "-bool", value ? "true" : "false"]
            } else if key == "autohide-delay", let value = backup.delay {
                arguments = ["write", "com.apple.dock", key, "-float", String(value)]
            } else {
                arguments = nil
            }
            if let arguments {
                succeeded = run("/usr/bin/defaults", arguments) && succeeded
            } else {
                let removed = run("/usr/bin/defaults", ["delete", "com.apple.dock", key])
                CFPreferencesAppSynchronize("com.apple.dock" as CFString)
                succeeded =
                    (removed
                        || CFPreferencesCopyAppValue(key as CFString, "com.apple.dock" as CFString) == nil)
                    && succeeded
            }
        }
        guard succeeded else {
            logger.error("Dock restoration failed; original settings backup retained")
            return false
        }
        try FileManager.default.removeItem(at: backupURL)
        _ = run("/usr/bin/killall", ["Dock"])
        return true
    }

    @discardableResult func enable() -> Bool {
        if isEnabled { return true }
        do {
            let lock = try Self.transactionLock()
            defer { withExtendedLifetime(lock) {} }
            if let previous = try Self.readBackup() {
                guard !Self.alive(previous.ownerPID), try Self.restoreUnlocked(previous) else { return false }
            }
            CFPreferencesAppSynchronize("com.apple.dock" as CFString)
            let backup = DockSnapshot(
                token: UUID().uuidString, ownerPID: getpid(),
                autohide: (CFPreferencesCopyAppValue("autohide" as CFString, "com.apple.dock" as CFString)
                    as? NSNumber)?.boolValue,
                delay: (CFPreferencesCopyAppValue("autohide-delay" as CFString, "com.apple.dock" as CFString)
                    as? NSNumber)?.doubleValue
            )
            let encoder = PropertyListEncoder()
            encoder.outputFormat = .xml
            try encoder.encode(backup).write(to: Self.backupURL, options: .atomic)
            token = backup.token
            do {
                let guardProcess = Process()
                guardProcess.executableURL = Bundle.main.executableURL
                guardProcess.arguments = ["--dock-guard", String(getpid()), backup.token]
                guardProcess.standardOutput = FileHandle.nullDevice
                guardProcess.standardError = FileHandle.nullDevice
                try guardProcess.run()
                guard
                    Self.run("/usr/bin/defaults", ["write", "com.apple.dock", "autohide", "-bool", "true"]),
                    Self.run(
                        "/usr/bin/defaults", ["write", "com.apple.dock", "autohide-delay", "-float", "3600"])
                else {
                    if try Self.restoreUnlocked(backup) { token = nil }
                    return false
                }
                _ = Self.run("/usr/bin/killall", ["Dock"])
                return true
            } catch {
                if try Self.restoreUnlocked(backup) { token = nil }
                throw error
            }
        } catch {
            Self.logger.error("Could not replace Dock: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    @discardableResult func restore() -> Bool {
        guard let token else { return true }
        do {
            let lock = try Self.transactionLock()
            defer { withExtendedLifetime(lock) {} }
            guard let backup = try Self.readBackup(), backup.token == token else { return false }
            let restored = try Self.restoreUnlocked(backup)
            if restored { self.token = nil }
            return restored
        } catch {
            Self.logger.error("Could not restore Dock: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    static func watch(pid: pid_t, token: String) {
        do {
            while let backup = try readBackup(), backup.token == token {
                if !alive(pid) {
                    let lock = try transactionLock()
                    defer { withExtendedLifetime(lock) {} }
                    if try restoreUnlocked(backup) { Diagnostics.shared.record(.dockGuardRestored) }
                    return
                }
                Thread.sleep(forTimeInterval: 1)
            }
        } catch { logger.error("Dock guard failed: \(error.localizedDescription, privacy: .public)") }
    }
}

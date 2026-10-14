import Darwin
import Foundation

/// Bounded event logs. Events contain no window titles, profile names, URLs or Dock tokens.
final class Diagnostics {
    static let shared = Diagnostics()
    enum Event: String {
        case launch, previousUncleanExit, shutdownRequested, shutdownFinished
        case dockRestoreFailed, dockGuardRestored, permissionChanged, scanFailed
        case shortcutsChanged, shortcutRegistrationFailed, installSucceeded, installFailed
        case previewUnavailable, exception
        case preferencesChanged, settingsChangeFailed
    }
    let directory: URL
    private let lock = NSLock()
    private let limit: Int
    private let pid: Int32
    private let isAlive: (Int32) -> Bool
    private var ownsMarker = false

    init(
        directory: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/WindowBar"),
        limit: Int = 524_288, pid: Int32 = getpid(),
        isAlive: @escaping (Int32) -> Bool = { kill($0, 0) == 0 || errno == EPERM }
    ) {
        self.directory = directory
        self.limit = limit
        self.pid = pid
        self.isAlive = isAlive
    }

    private var marker: URL { directory.appendingPathComponent("session.json") }

    func startSession() {
        lock.lock()
        defer { lock.unlock() }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: marker),
            let previous = try? JSONDecoder().decode(Int32.self, from: data), !isAlive(previous)
        {
            append(.previousUncleanExit)
        }
        if let data = try? JSONEncoder().encode(pid) {
            do {
                try data.write(to: marker, options: .atomic)
                ownsMarker = true
            } catch {}
        }
        append(.launch)
    }

    func finishSession(restoredDock: Bool) {
        lock.lock()
        defer { lock.unlock() }
        append(restoredDock ? .shutdownFinished : .dockRestoreFailed)
        if restoredDock && ownsMarker,
            let data = try? Data(contentsOf: marker),
            (try? JSONDecoder().decode(Int32.self, from: data)) == pid
        {
            try? FileManager.default.removeItem(at: marker)
        }
        ownsMarker = false
    }

    func record(_ event: Event) {
        guard lock.try() else { return }
        defer { lock.unlock() }
        append(event)
    }

    private func append(_ event: Event) {
        do {
            let manager = FileManager.default
            try manager.createDirectory(at: directory, withIntermediateDirectories: true)
            let transaction = try InstanceLock(directory: directory, name: "events.lock")
            defer { withExtendedLifetime(transaction) {} }
            let url = directory.appendingPathComponent("events.jsonl")
            if let attributes = try? manager.attributesOfItem(atPath: url.path),
                (attributes[.size] as? NSNumber)?.intValue ?? 0 >= limit
            {
                let rotated = directory.appendingPathComponent("events.previous.jsonl")
                if manager.fileExists(atPath: rotated.path) { try manager.removeItem(at: rotated) }
                try manager.moveItem(at: url, to: rotated)
            }
            let values: [String: Any] = [
                "time": ISO8601DateFormatter().string(from: Date()), "event": event.rawValue, "pid": pid,
            ]
            var data = try JSONSerialization.data(withJSONObject: values, options: .sortedKeys)
            data.append(10)
            if !manager.fileExists(atPath: url.path) { manager.createFile(atPath: url.path, contents: nil) }
            let file = try FileHandle(forWritingTo: url)
            defer { try? file.close() }
            try file.seekToEnd()
            try file.write(contentsOf: data)
        } catch {
            // Diagnostics must never prevent normal app operation or Dock restoration.
        }
    }
}

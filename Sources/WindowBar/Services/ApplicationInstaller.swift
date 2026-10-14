import AppKit

final class ApplicationInstaller {
    let destination: URL
    private let isRunning: (URL) -> Bool
    private let verify: (URL) throws -> Void

    init(
        destination: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications/WindowBar.app"),
        isRunning: @escaping (URL) -> Bool = { url in
            NSWorkspace.shared.runningApplications.contains {
                $0.bundleURL?.resolvingSymlinksInPath() == url.resolvingSymlinksInPath()
            }
        },
        verify: @escaping (URL) throws -> Void = { url in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
            process.arguments = ["--verify", "--strict", url.path]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { throw InstallError.invalidBundle }
        }
    ) {
        self.destination = destination
        self.isRunning = isRunning
        self.verify = verify
    }

    /// Install atomically; never overwrite a running copy. A failed swap keeps the old app.
    func install(from source: URL) throws {
        let manager = FileManager.default
        guard source.pathExtension == "app", destination.pathExtension == "app",
            Bundle(url: source)?.bundleIdentifier == "local.windowbar.app"
        else { throw InstallError.invalidBundle }
        guard source.resolvingSymlinksInPath() != destination.resolvingSymlinksInPath() else { return }
        guard !isRunning(destination) else { throw InstallError.runningCopy }
        try verify(source)
        let directory = destination.deletingLastPathComponent()
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        let stage = directory.appendingPathComponent(".WindowBar-install-\(UUID().uuidString).app")
        let backup = directory.appendingPathComponent(".WindowBar-previous-\(UUID().uuidString).app")
        defer { try? manager.removeItem(at: stage) }
        try manager.copyItem(at: source, to: stage)
        try verify(stage)
        // Recheck after copying, before changing the installed path.
        guard !isRunning(destination) else { throw InstallError.runningCopy }
        let exists = manager.fileExists(atPath: destination.path)
        if exists { try manager.moveItem(at: destination, to: backup) }
        do {
            try manager.moveItem(at: stage, to: destination)
        } catch {
            if exists { try? manager.moveItem(at: backup, to: destination) }
            throw error
        }
        if exists { try? manager.removeItem(at: backup) }
    }

    enum InstallError: LocalizedError {
        case runningCopy, invalidBundle
        var errorDescription: String? {
            switch self {
            case .runningCopy:
                return "The installed copy is running. Quit that copy before installing an update."
            case .invalidBundle: return "This is not a valid signed WindowBar app."
            }
        }
    }
}

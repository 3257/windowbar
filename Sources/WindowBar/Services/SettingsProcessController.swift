import AppKit

extension Notification.Name {
    static let windowBarSettingsShow = Notification.Name("local.windowbar.settings.show")
    static let windowBarPreferencesChanged = Notification.Name("local.windowbar.preferences.changed")
    static let windowBarPreferencesApplied = Notification.Name("local.windowbar.preferences.applied")
    static let windowBarPreferencesRejected = Notification.Name("local.windowbar.preferences.rejected")
}

/// Settings may enter AppKit rendering/file dialogs. Keep those waits out of the taskbar process.
final class SettingsProcessController {
    private var process: Process?
    private let executable: URL
    private let arguments: [String]
    private let notificationsEnabled: Bool
    var processIdentifier: Int32? { process?.isRunning == true ? process?.processIdentifier : nil }

    init(
        executable: URL = Bundle.main.executableURL!, arguments: [String] = ["--settings"],
        notificationsEnabled: Bool = true
    ) {
        self.executable = executable
        self.arguments = arguments
        self.notificationsEnabled = notificationsEnabled
    }

    func show() throws {
        if process?.isRunning == true {
            guard notificationsEnabled else { return }
            DistributedNotificationCenter.default().postNotificationName(
                .windowBarSettingsShow, object: nil, userInfo: nil, deliverImmediately: true)
            return
        }
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        self.process = process
    }

    func stop() {
        if process?.isRunning == true { process?.terminate() }
        process = nil
    }

    func preferencesApplied() {
        guard notificationsEnabled else { return }
        DistributedNotificationCenter.default().postNotificationName(
            .windowBarPreferencesApplied, object: nil, userInfo: nil, deliverImmediately: true)
    }
}

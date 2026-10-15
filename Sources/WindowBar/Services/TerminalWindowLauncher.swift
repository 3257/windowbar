import AppKit

/// Send a folder directly to Terminal, keeping its default profile and login shell.
/// Never use the folder's default handler or type a command into an existing tab.
final class TerminalWindowLauncher {
    private let homeDirectory: URL
    private let open: (URL, URL) -> Void

    init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        open: @escaping (URL, URL) -> Void = TerminalWindowLauncher.openFolder
    ) {
        self.homeDirectory = homeDirectory
        self.open = open
    }

    func openHome(in application: URL) {
        open(homeDirectory, application)
    }

    func newWindowItem(in application: URL) -> NSMenuItem {
        ActionMenuItem("New Window") { [self] in openHome(in: application) }
    }

    private static func openFolder(_ folder: URL, in application: URL) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open([folder], withApplicationAt: application, configuration: configuration) {
            _, error in
            if error != nil { DispatchQueue.main.async { NSSound.beep() } }
        }
    }
}

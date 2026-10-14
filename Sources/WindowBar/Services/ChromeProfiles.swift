import AppKit
import OSLog
import WindowBarCore

protocol ChromeProfileProviding {
    func profiles(for launcher: LauncherEntry) -> [ChromeProfile]?
}

final class ChromeProfileStore: ChromeProfileProviding {
    private let supportDirectory: URL
    private let logger = Logger(subsystem: "local.windowbar.app", category: "ChromeProfiles")

    init(
        supportDirectory: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
            "Library/Application Support")
    ) {
        self.supportDirectory = supportDirectory
    }

    func profiles(for launcher: LauncherEntry) -> [ChromeProfile]? {
        let locations = [
            "com.google.Chrome": "Google/Chrome",
            "com.google.Chrome.beta": "Google/Chrome Beta",
            "com.google.Chrome.dev": "Google/Chrome Dev",
            "com.google.Chrome.canary": "Google/Chrome Canary",
        ]
        guard let identifier = Bundle(url: launcher.url)?.bundleIdentifier,
            let location = locations[identifier]
        else { return nil }
        do {
            let url = supportDirectory.appendingPathComponent(location).appendingPathComponent("Local State")
            return try ChromeProfile.decodeLocalState(Data(contentsOf: url))
        } catch {
            logger.error("Chrome profile metadata is unavailable; no Chrome files were changed")
            return []
        }
    }
}

struct SampleChromeProfiles: ChromeProfileProviding {
    func profiles(for launcher: LauncherEntry) -> [ChromeProfile]? {
        guard launcher.name == "Google Chrome" else { return nil }
        return [
            ChromeProfile(directory: "Default", name: "Personal"),
            ChromeProfile(directory: "Profile 1", name: "Work", lastUsed: true),
            ChromeProfile(directory: "Profile 2", name: "Development"),
            ChromeProfile(directory: "Profile 3", name: "Client"),
        ]
    }
}

final class ChromeProfileLauncher {
    func open(_ profile: ChromeProfile, in launcher: LauncherEntry) {
        guard ChromeProfile.validDirectory(profile.directory) else {
            NSSound.beep()
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.arguments = profile.launchArguments
        // Chrome forwards the new process's profile arguments to its existing browser.
        configuration.createsNewApplicationInstance = true
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: launcher.url, configuration: configuration) { _, error in
            if error != nil { DispatchQueue.main.async { NSSound.beep() } }
        }
    }
}

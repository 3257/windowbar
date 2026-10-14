import AppKit
import WindowBarCore

/// Adds WindowBar's management actions without changing an app's native Dock actions.
final class BarManagementMenus {
    private let features: FeatureCoordinator
    private let profiles: ChromeProfileProviding
    private let application: (WindowEntry) -> LauncherEntry?
    var onPinsChanged: (() -> Void)?
    var onOrderChanged: (() -> Void)?
    var onRefresh: (() -> Void)?
    var onError: ((Error) -> Void)?

    init(
        features: FeatureCoordinator, profiles: ChromeProfileProviding = ChromeProfileStore(),
        application: @escaping (WindowEntry) -> LauncherEntry? = { entry in
            guard let app = NSRunningApplication(processIdentifier: entry.pid), let url = app.bundleURL else {
                return nil
            }
            return LauncherEntry(url: url, name: entry.appName, icon: app.icon ?? NSImage())
        }
    ) {
        self.features = features
        self.profiles = profiles
        self.application = application
    }

    func augmentLauncher(_ menu: NSMenu, launcher: LauncherEntry, launchers: [LauncherEntry]) {
        menu.addItem(.separator())
        menu.addItem(
            ActionMenuItem("Unpin from WindowBar") { [weak self] in
                guard let self else { return }
                self.changePins { try self.features.unpin(launcher.url) }
            })
        guard let index = launchers.firstIndex(where: { $0.url == launcher.url }) else { return }
        for (title, offset) in [("Move left", -1), ("Move right", 1)] {
            let target = index + offset
            guard launchers.indices.contains(target) else { continue }
            let neighbor = launchers[target]
            menu.addItem(
                ActionMenuItem(title) { [weak self] in
                    guard let self else { return }
                    self.changePins {
                        try self.features.moveLauncher(
                            launcher.url.path, relativeTo: neighbor.url.path, after: offset > 0)
                    }
                })
        }
    }

    func augmentWindow(_ menu: NSMenu, entry: WindowEntry, entries: [WindowEntry]) {
        menu.addItem(.separator())
        if let launcher = application(entry) {
            let pinned =
                features.preferences.value.pinnedPaths?.contains(launcher.url.standardizedFileURL.path)
                == true
            menu.addItem(
                ActionMenuItem(pinned ? "Unpin App from WindowBar" : "Pin App to WindowBar") { [weak self] in
                    guard let self else { return }
                    self.changePins {
                        if pinned {
                            try self.features.unpin(launcher.url)
                        } else {
                            try self.features.pin(launcher.url)
                        }
                    }
                })
            if let profiles = profiles.profiles(for: launcher), !profiles.isEmpty {
                let heading = NSMenuItem(title: "Profile Badge", action: nil, keyEquivalent: "")
                let submenu = NSMenu()
                let automatic = ActionMenuItem("Automatic") { [weak self] in
                    self?.features.setProfile(nil, for: entry.id)
                    self?.onRefresh?()
                }
                automatic.state = features.profileOverride(for: entry.id) == nil ? .on : .off
                submenu.addItem(automatic)
                let counts = Dictionary(grouping: profiles, by: \.name).mapValues(\.count)
                for profile in profiles {
                    let label =
                        counts[profile.name, default: 0] > 1
                        ? "\(profile.name) (\(profile.directory))" : profile.name
                    let item = ActionMenuItem(label) { [weak self] in
                        let badge = ChromeProfile(
                            directory: profile.directory, name: label, lastUsed: profile.lastUsed)
                        self?.features.setProfile(badge, for: entry.id)
                        self?.onOrderChanged?()
                    }
                    item.state =
                        features.profileOverride(for: entry.id)?.directory == profile.directory ? .on : .off
                    submenu.addItem(item)
                }
                heading.submenu = submenu
                menu.addItem(heading)
            }
        }
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        for (title, offset) in [("Move left", -1), ("Move right", 1)] {
            let target = index + offset
            guard entries.indices.contains(target) else { continue }
            let id = entries[target].id
            menu.addItem(
                ActionMenuItem(title) { [weak self] in
                    self?.features.moveWindow(entry.id, relativeTo: id, after: offset > 0)
                    self?.onOrderChanged?()
                })
        }
    }

    private func changePins(_ change: () throws -> Void) {
        do {
            try change()
            onPinsChanged?()
        } catch { onError?(error) }
    }
}

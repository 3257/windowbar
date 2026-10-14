import AppKit
import WindowBarCore

/// Isolated native service checks: no live hotkeys, login items, capture, Dock writes or activation.
enum FeatureVerification {
    enum Failure: Error { case check(String) }
    static func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw Failure.check(message) }
    }

    final class LoginBackend: LoginItemBackend {
        var status: StartupStatus = .disabled
        var registrations = 0
        func register() throws {
            registrations += 1
            status = .enabled
        }
        func unregister() throws { status = .disabled }
    }

    final class HotKeys: HotKeyBackend {
        var onPressed: ((UInt32) -> Void)?
        var installed: [ShortcutBinding] = []
        var rejectedKey: UInt32?
        func register(_ binding: ShortcutBinding, identifier: UInt32) throws {
            if binding.keyCode == rejectedKey { throw Failure.check("simulated shortcut conflict") }
            installed.append(binding)
        }
        func unregisterAll() { installed = [] }
    }

    final class Capture: WindowCaptureBackend {
        var hasPermission = false
        var captures = 0
        func capture(_ entry: WindowEntry, completion: @escaping (NSImage?) -> Void) {
            captures += 1
            completion(NSImage(size: NSSize(width: 120, height: 80)))
        }
    }

    final class Dock: DockReplacing {
        var isEnabled = false
        var restored = 0
        func enable() -> Bool {
            isEnabled = true
            return true
        }
        func restore() -> Bool {
            restored += 1
            isEnabled = false
            return true
        }
    }

    static func run() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "WindowBar-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let suite = "local.windowbar.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = PreferencesStore(defaults: defaults)
        let features = FeatureCoordinator(preferences: preferences)

        let login = LoginBackend()
        let startup = LoginItemService(backend: login, installed: { true })
        try startup.setEnabled(true)
        try require(startup.status == .enabled && login.registrations == 1, "Start at login did not register")
        try startup.setEnabled(false)
        try require(startup.status == .disabled, "Start at login did not unregister")
        do {
            try LoginItemService(backend: login, installed: { false }).setEnabled(true)
            throw Failure.check("Uninstalled app was registered")
        } catch LoginItemService.ServiceError.installFirst {}
        print("PASS: login registration, disable, and installation prerequisite")

        let source = directory.appendingPathComponent("Source.app")
        let contents = source.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist = ["CFBundleIdentifier": "local.windowbar.app", "CFBundlePackageType": "APPL"]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))
        let destination = directory.appendingPathComponent("Applications/WindowBar.app")
        let installer = ApplicationInstaller(
            destination: destination, isRunning: { _ in false }, verify: { _ in })
        try installer.install(from: source)
        try require(FileManager.default.fileExists(atPath: destination.path), "App installation failed")
        do {
            try ApplicationInstaller(destination: destination, isRunning: { _ in true }, verify: { _ in })
                .install(from: source)
            throw Failure.check("Running app was overwritten")
        } catch ApplicationInstaller.InstallError.runningCopy {}
        try require(
            FileManager.default.fileExists(atPath: destination.path), "Original installed app was lost")
        print("PASS: staged installation and protection for running copies")

        try preferences.importLaunchersIfNeeded([])
        try features.pin(source)
        try features.pin(destination)
        try features.moveLauncher(destination.path, before: source.path)
        try require(
            preferences.value.pinnedPaths == [destination.path, source.path], "Pinned app reorder failed")
        try require(
            PreferencesStore(defaults: defaults).value == preferences.value,
            "Pinned preferences did not persist")
        try features.unpin(source)
        try features.unpin(destination)
        try preferences.importLaunchersIfNeeded([LauncherEntry(url: source, name: "Sample", icon: NSImage())])
        try require(preferences.value.pinnedPaths == [], "Empty pinned list was reimported from Dock")
        print("PASS: pin, unpin, reorder, persistence, and intentional empty pin list")

        var entries = sampleWindows()
        let profile = ChromeProfile(directory: "Profile 3", name: "Client")
        features.setProfile(profile, for: entries[0].id)
        try require(features.ordered(entries)[0].profile == profile, "Profile override was not applied")
        features.setProfile(nil, for: entries[0].id)
        try require(
            features.ordered(entries)[0].profile == entries[0].profile,
            "Automatic profile mode was not restored")
        features.moveWindow(entries[2].id, before: entries[0].id)
        try require(features.ordered(entries).first?.id == entries[2].id, "Window reorder was lost on scan")
        print("PASS: window reordering and manual/automatic profile badges")

        let sampleLauncher = LauncherEntry(url: source, name: "Google Chrome", icon: NSImage())
        let menus = BarManagementMenus(
            features: features, profiles: SampleChromeProfiles(), application: { _ in sampleLauncher })
        let windowMenu = NSMenu()
        menus.augmentWindow(windowMenu, entry: entries[0], entries: entries)
        guard let badgeMenu = windowMenu.items.first(where: { $0.title == "Profile Badge" })?.submenu,
            let clientIndex = badgeMenu.items.firstIndex(where: { $0.title == "Client" }),
            let pinIndex = windowMenu.items.firstIndex(where: { $0.title == "Pin App to WindowBar" })
        else { throw Failure.check("Management menu is missing profile/pin actions") }
        try require(badgeMenu.items.count == 5, "Profile badge menu omitted a profile")
        badgeMenu.performActionForItem(at: clientIndex)
        try require(
            features.ordered(entries).first(where: { $0.id == entries[0].id })?.profile?.name == "Client",
            "Profile menu action failed")
        windowMenu.performActionForItem(at: pinIndex)
        try require(preferences.value.pinnedPaths == [source.path], "Window menu pin action failed")
        let launcherMenu = NSMenu()
        launcherMenu.addItem(NSMenuItem(title: "New Tab", action: nil, keyEquivalent: ""))
        menus.augmentLauncher(launcherMenu, launcher: sampleLauncher, launchers: [sampleLauncher])
        try require(
            launcherMenu.items.first?.title == "New Tab", "Pin management replaced native app actions")
        let unpin = launcherMenu.items.firstIndex { $0.title == "Unpin from WindowBar" }!
        launcherMenu.performActionForItem(at: unpin)
        try require(preferences.value.pinnedPaths == [], "Pinned menu unpin action failed")
        print("PASS: native pin/unpin/profile menu actions preserve existing app commands")

        entries[0].frame = CGRect(x: 20, y: 20, width: 400, height: 400)
        entries[1].frame = CGRect(x: 1200, y: 20, width: 400, height: 400)
        let displays = [
            DisplayRegion(id: 1, frame: CGRect(x: 0, y: 0, width: 1000, height: 1000)),
            DisplayRegion(id: 2, frame: CGRect(x: 1000, y: 0, width: 1000, height: 1000)),
        ]
        var updated = preferences.value
        updated.windowScope = .currentDisplay
        try preferences.save(updated)
        try require(
            features.visible(entries, displayID: 1, displays: displays).contains { $0.id == entries[0].id },
            "Display's own window missing")
        try require(
            !features.visible(entries, displayID: 1, displays: displays).contains { $0.id == entries[1].id },
            "Another display's window leaked")
        updated.windowScope = .allDisplays
        try preferences.save(updated)
        try require(
            features.visible(entries, displayID: 1, displays: displays).count == entries.count,
            "All displays mode filtered windows")
        print("PASS: per-display and all-display filtering")

        let backend = HotKeys()
        let hotkeys = GlobalShortcuts(backend: backend)
        var actions: [ShortcutAction] = []
        hotkeys.onAction = { actions.append($0) }
        try hotkeys.configure(ShortcutBinding.defaults)
        backend.onPressed?(1)
        backend.onPressed?(3)
        backend.onPressed?(99)
        try require(actions == [.nextWindow, .pinned1], "Shortcut routing failed")
        backend.rejectedKey = 0
        var changed = ShortcutBinding.defaults
        changed[0].keyCode = 0
        do {
            try hotkeys.configure(changed)
            throw Failure.check("Shortcut conflict accepted")
        } catch CarbonHotKeyBackend.RegistrationError.conflict {} catch Failure.check(let reason)
            where reason == "simulated shortcut conflict"
        {}
        try require(
            hotkeys.bindings == ShortcutBinding.defaults && backend.installed == ShortcutBinding.defaults,
            "Hotkey conflict did not roll back")
        try hotkeys.configure([])
        try require(backend.installed.isEmpty, "Disabled shortcuts stayed registered")
        print("PASS: keyboard routing, conflicts, rollback, and disable")

        let capture = Capture()
        let previews = WindowPreviews(backend: capture)
        var entry = entries[0]
        entry.windowID = 42
        var unavailable = false
        previews.preview(entry) { if case .unavailable = $0 { unavailable = true } }
        try require(unavailable && capture.captures == 0, "Hover attempted capture without permission")
        capture.hasPermission = true
        var received = false
        previews.preview(entry) { if case .image = $0 { received = true } }
        let deadline = Date().addingTimeInterval(2)
        while !received && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
        try require(received && capture.captures == 1, "Permitted hover did not return image")
        previews.preview(entry) { _ in }
        try require(capture.captures == 1, "Preview cache failed")
        print("PASS: preview permission gate, image delivery, and bounded cache")

        let logDirectory = directory.appendingPathComponent("logs")
        let diagnostics = Diagnostics(directory: logDirectory, limit: 200, pid: 123, isAlive: { _ in false })
        diagnostics.startSession()
        for _ in 0..<10 { diagnostics.record(.shortcutsChanged) }
        diagnostics.finishSession(restoredDock: true)
        try require(
            !FileManager.default.fileExists(atPath: logDirectory.appendingPathComponent("session.json").path),
            "Clean shutdown left a marker")
        try require(
            FileManager.default.fileExists(
                atPath: logDirectory.appendingPathComponent("events.previous.jsonl").path),
            "Diagnostics rotation failed")
        let crashed = Diagnostics(directory: logDirectory, pid: 234, isAlive: { _ in false })
        crashed.startSession()
        let recovery = Diagnostics(directory: logDirectory, pid: 345, isAlive: { _ in false })
        recovery.startSession()
        let log = try String(contentsOf: logDirectory.appendingPathComponent("events.jsonl"))
        try require(log.contains("previousUncleanExit"), "Unclean exit was not detected")
        try require(
            !log.contains("Work") && !log.contains("Project dashboard"),
            "Diagnostics included personal content")
        print("PASS: diagnostics rotation, clean shutdown, and unclean-exit detection")

        let lifecycleLog = Diagnostics(
            directory: directory.appendingPathComponent("lifecycle"), pid: 678, isAlive: { _ in false })
        lifecycleLog.startSession()
        let dock = Dock()
        let delegate = AppDelegate(dock: dock, features: features, diagnostics: lifecycleLog)
        delegate.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
        try require(dock.restored == 1, "Application shutdown did not restore its injected Dock")
        try require(
            !FileManager.default.fileExists(
                atPath: lifecycleLog.directory.appendingPathComponent("session.json").path),
            "Application shutdown did not finish its diagnostic session")
        print("PASS: application shutdown restores Dock and finishes diagnostics through injected services")
        try FeatureViewVerification.run(features: features, directory: directory)
        print("PASS: all feature service and native UI checks completed without changing the running desktop")
    }
}

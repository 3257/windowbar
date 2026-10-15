import AppKit

enum SettingsIsolationVerification {
    static func run(features: FeatureCoordinator, directory: URL) throws {
        let require = FeatureVerification.require
        let process = SettingsProcessController(
            executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["5"], notificationsEnabled: false)
        defer { process.stop() }
        try process.show()
        guard let pid = process.processIdentifier else {
            throw FeatureVerification.Failure.check("Settings worker failed to start")
        }
        try process.show()
        try require(process.processIdentifier == pid, "Opening settings launched duplicate helpers")
        let bar = BarView(frame: NSRect(x: 0, y: 0, width: 1000, height: 66))
        bar.update(entries: sampleWindows(), trusted: true)
        bar.layoutSubtreeIfNeeded()
        var selected = false
        bar.onSelect = { _ in selected = true }
        FeatureViewVerification.descendants(bar).compactMap { $0 as? WindowButton }.first?.performClick(nil)
        try require(
            selected && process.processIdentifier == pid,
            "Waiting settings process blocked taskbar interaction")
        process.stop()
        try require(process.processIdentifier == nil, "Settings helper did not stop independently")
        print("PASS: waiting settings helper stays separate while taskbar layout and selection respond")

        let settings = SettingsWindowController(
            features: features,
            startup: LoginItemService(backend: FeatureVerification.LoginBackend(), installed: { true }),
            logDirectory: directory, decorateWindow: false)
        defer { settings.close() }
        for tab in settings.tabs.tabViewItems {
            settings.tabs.selectTabViewItem(tab)
            guard let view = tab.view, let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)
            else {
                throw FeatureVerification.Failure.check("Settings tab rendering unavailable")
            }
            view.cacheDisplay(in: view.bounds, to: bitmap)
            try require(bitmap.pixelsWide > 0, "Settings tab rendered empty")
        }
        try require(
            settings.tabs.selectedTabViewItem?.label == "Diagnostics" && !settings.window!.isVisible,
            "Diagnostics tab selection failed or displayed a test window")
        print("PASS: every settings tab, including Diagnostics, selects and renders offscreen")
    }
}

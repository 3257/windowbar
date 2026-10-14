import AppKit
import WindowBarCore

/// Exercises native controls against fixture windows; never posts input or activates an app.
enum WindowToolsVerification {
    static func run(features: FeatureCoordinator, directory: URL) throws {
        let require = FeatureVerification.require
        let entries = sampleWindows()
        let switcher = WindowSwitcherController()
        defer { switcher.close() }
        var preferences = BarPreferences()
        switcher.update(entries: entries, preferences: preferences)
        switcher.search.stringValue = "chrome work"
        switcher.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
        try require(
            switcher.results.count == 1 && switcher.results[0].profile?.name == "Work",
            "Search did not match app and profile")
        var chosen: String?
        switcher.onSelect = { chosen = $0.id }
        let returnKey = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, characters: "\r", charactersIgnoringModifiers: "\r",
            isARepeat: false, keyCode: 36)!
        switcher.table.keyDown(with: returnKey)
        try require(chosen == switcher.results.first?.id, "Return did not select search result")
        switcher.search.stringValue = ""
        switcher.filter()
        switcher.handleCommand(#selector(NSResponder.moveDown(_:)))
        try require(switcher.table.selectedRow == 1, "Search arrow navigation failed")
        switcher.handleCommand(#selector(NSResponder.moveUp(_:)))
        try require(switcher.table.selectedRow == 0, "Search up navigation failed")
        switcher.update(entries: [], preferences: preferences)
        chosen = nil
        switcher.chooseSelection()
        try require(chosen == nil && !switcher.emptyLabel.isHidden, "Search selected a closed window")
        let minimized = WindowEntry(
            id: "minimized", pid: 0, appName: "Terminal", title: "fixture",
            icon: nil, element: nil, minimized: true, focused: false)
        preferences.searchIncludesMinimized = false
        switcher.update(entries: entries + [minimized], preferences: preferences)
        try require(!switcher.results.contains { $0.minimized }, "Search ignored minimized setting")
        var cancelled = false
        switcher.onCancel = { cancelled = true }
        switcher.handleCommand(#selector(NSResponder.cancelOperation(_:)))
        try require(cancelled, "Escape did not dismiss search")
        preferences.searchEnabled = false
        switcher.update(entries: entries, preferences: preferences)
        switcher.present()
        try require(switcher.results.isEmpty && switcher.window?.isVisible == false, "Disabled search opened")
        print(
            "PASS: search native query, keyboard selection, stale/empty results, minimized toggle, and disable"
        )

        let panel = TaskbarPanel(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 66),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        defer { panel.close() }
        let bar = BarView(frame: NSRect(origin: .zero, size: panel.frame.size))
        panel.contentView = bar
        preferences = BarPreferences()
        preferences.groupingMode = .app
        let previous = features.preferences.value
        try features.preferences.save(preferences)
        let interleaved = [entries[0], entries[3], entries[1], entries[4], entries[2]]
        try require(
            features.navigationEntries(interleaved).map(\.id)
                == [entries[0], entries[1], entries[2], entries[3], entries[4]].map(\.id),
            "Keyboard navigation did not follow grouped row order")
        try features.preferences.save(previous)
        bar.update(entries: entries, trusted: true, preferences: preferences)
        bar.layoutSubtreeIfNeeded()
        let descendants = FeatureViewVerification.descendants
        var searchClicked = false
        bar.onSearch = { searchClicked = true }
        bar.searchButton.performClick(nil)
        try require(searchClicked, "Search button did not route opening intent")
        let headers = descendants(bar).compactMap { $0 as? WindowGroupButton }
        let windows = descendants(bar).compactMap { $0 as? WindowButton }
        try require(headers.count == 2, "App groups were not rendered")
        let chrome = headers.first { $0.title.contains("Chrome") }!
        chrome.performClick(nil)
        bar.layoutSubtreeIfNeeded()
        try require(
            windows.filter { $0.entry.appName == "Google Chrome" }.allSatisfy(\.isHidden),
            "Collapse did not hide Chrome windows")
        bar.update(entries: entries, trusted: true, preferences: preferences)
        try require(chrome.title.hasPrefix("▸"), "Scan reset collapsed group")
        bar.revealWindow(entries[0].id)
        try require(
            !windows.first { $0.entry.id == entries[0].id }!.isHidden, "Selection did not expand its group")
        preferences.groupingMode = .appAndProfile
        bar.update(entries: entries, trusted: true, preferences: preferences)
        try require(
            descendants(bar).compactMap { $0 as? WindowGroupButton }.count == 4, "Profile groups missing")
        preferences.groupingMode = .none
        preferences.searchEnabled = false
        bar.update(entries: entries, trusted: true, preferences: preferences)
        try require(
            descendants(bar).compactMap { $0 as? WindowGroupButton }.isEmpty
                && windows.allSatisfy { !$0.isHidden } && bar.searchButton.isHidden,
            "Disabled grouping/search did not restore individual windows")
        print("PASS: native app/profile grouping, collapse persistence, selection expansion, and flat mode")

        let hover = HoverPreviewController(
            provider: FeatureViewVerification.DeferredPreview(), showWindows: false)
        let target = windows.first { !$0.entry.minimized }!
        var actions: [String] = []
        hover.onSelect = { actions.append("select:" + $0.id) }
        hover.onMinimize = { actions.append("minimize:" + $0.id) }
        hover.onClose = { actions.append("close:" + $0.id) }
        var stale: NSButton?
        for action in ["select", "minimize", "close"] {
            hover.hover(target.entry, button: target, entered: true, mode: .titles, actionsEnabled: true)
            FeatureViewVerification.wait(0.52)
            guard let button = hover.actionButtons[action] else {
                throw FeatureVerification.Failure.check("Missing hover action")
            }
            stale = button
            hover.hover(target.entry, button: target, entered: false, mode: .titles, actionsEnabled: true)
            try require(
                hover.shownEntryID == target.entry.id, "Leaving button dismissed interactive card immediately"
            )
            button.performClick(nil)
            try require(
                actions.last == action + ":" + target.entry.id && hover.shownEntryID == nil,
                "Hover action routed incorrectly")
        }
        let restored = WindowButton(entry: minimized)
        bar.addSubview(restored)
        restored.frame = NSRect(x: 10, y: 7, width: 140, height: 52)
        hover.hover(minimized, button: restored, entered: true, mode: .titles, actionsEnabled: true)
        FeatureViewVerification.wait(0.52)
        stale?.performClick(nil)
        try require(actions.count == 3, "Stale hover action targeted another window")
        try require(hover.actionButtons["minimize"]?.title == "Restore", "Minimized window lacks Restore")
        hover.actionButtons["minimize"]?.performClick(nil)
        try require(actions.last == "select:minimized", "Restore did not use selection/unminimize path")
        hover.hover(target.entry, button: target, entered: true, mode: .titles, actionsEnabled: false)
        FeatureViewVerification.wait(0.52)
        try require(hover.actionButtons.isEmpty, "Disabled hover actions still rendered")
        hover.updatePointer(NSPoint(x: -9000, y: -9000), now: 10)
        hover.updatePointer(NSPoint(x: -9000, y: -9000), now: 11)
        try require(hover.shownEntryID == nil, "Hover card did not dismiss after pointer left")
        print(
            "PASS: hover Switch/Minimize/Restore/Close, pointer transition, stale-action protection, and disable"
        )

        let autoHide = BarAutoHideController()
        let shown = NSRect(x: -990, y: -492, width: 900, height: 66)
        let screen = NSRect(x: -1000, y: -500, width: 1000, height: 800)
        autoHide.layout(shownFrame: shown, screenFrame: screen, panel: panel)
        func tick(
            _ now: Double, point: NSPoint = NSPoint(x: 2000, y: 2000), interaction: Bool = false,
            enabled: Bool = true
        ) {
            autoHide.update(
                panel: panel, enabled: enabled, delay: 0.8, pointer: point,
                interaction: interaction, now: now, animated: false)
        }
        tick(0)
        tick(1)
        try require(
            autoHide.hidden && panel.frame == autoHide.edgeFrame && panel.ignoresMouseEvents,
            "Auto-hide did not leave a nonintercepting edge strip")
        let displayBelow = NSRect(x: screen.minX, y: screen.minY - 800, width: screen.width, height: 800)
        try require(!panel.frame.intersects(displayBelow), "Hidden bar appeared on the display below")
        autoHide.layout(shownFrame: shown, screenFrame: screen, panel: panel)
        try require(autoHide.hidden, "Refresh revealed hidden bar")
        tick(1.1, point: NSPoint(x: shown.midX, y: screen.minY + 1))
        try require(
            !autoHide.hidden && panel.frame == shown && panel.contentView === bar
                && !panel.ignoresMouseEvents,
            "Bottom edge did not restore the interactive bar")
        tick(2)
        tick(3, interaction: true)
        try require(!autoHide.hidden, "Menu/preview/drag interaction did not keep bar open")
        tick(4)
        tick(5)
        tick(6, enabled: false)
        try require(panel.frame == shown && !autoHide.hidden, "Disabling auto-hide did not restore bar")
        try require(!panel.isVisible && switcher.window?.isVisible == false, "Feature checks showed windows")
        print(
            "PASS: native auto-hide frames, negative display coordinates, edge reveal, interaction hold, and disable"
        )

        let settings = SettingsWindowController(
            features: features,
            startup: LoginItemService(backend: FeatureVerification.LoginBackend(), installed: { true }),
            logDirectory: directory)
        defer { settings.close() }
        settings.searchToggle.state = .off
        settings.minimizedToggle.state = .off
        settings.grouping.selectItem(at: 2)
        settings.hoverActionsToggle.state = .off
        settings.autoHideToggle.state = .on
        settings.hideDelay.doubleValue = 1.5
        settings.changeBehavior()
        let saved = features.preferences.value
        try require(
            !saved.searchEnabled && !saved.searchIncludesMinimized && saved.groupingMode == .appAndProfile
                && !saved.hoverActionsEnabled && saved.autoHideEnabled && saved.autoHideDelay == 1.5,
            "Behavior controls did not persist all feature settings")
        try require(
            !settings.minimizedToggle.isEnabled && settings.hideDelay.isEnabled,
            "Dependent settings controls were not updated")
        try require(
            settings.tabs.tabViewItems.contains { $0.label == "Behavior" }
                && settings.window?.isVisible == false,
            "Behavior tab missing or visible")
        print("PASS: all four feature settings and delay persist through native controls")
    }
}

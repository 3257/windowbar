import AppKit
import WindowBarCore

enum PinsPeekVerification {
    static func run(features: FeatureCoordinator, directory: URL) throws {
        let require = FeatureVerification.require
        let panel = TaskbarPanel(
            contentRect: CGRect(x: 0, y: 0, width: 1000, height: 66),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        defer { panel.close() }
        let bar = BarView(frame: CGRect(origin: .zero, size: panel.frame.size))
        panel.contentView = bar
        let entries = sampleWindows()
        let launchers = sampleLaunchers()
        var preferences = BarPreferences()
        bar.update(entries: entries, trusted: true, launchers: launchers, preferences: preferences)
        bar.layoutSubtreeIfNeeded()
        try require(bar.launchScroll.frame.minX > bar.scroll.frame.maxX, "Default pins are not on the right")
        preferences.pinnedSide = .left
        bar.update(entries: entries, trusted: true, launchers: launchers, preferences: preferences)
        bar.layoutSubtreeIfNeeded()
        try require(bar.launchScroll.frame.maxX < bar.scroll.frame.minX, "Left pins overlap window row")
        let pins = FeatureViewVerification.descendants(bar).compactMap { $0 as? LauncherButton }
        var pinHovered = false
        bar.onLauncherHover = { _, windows, _, entered in pinHovered = entered && !windows.isEmpty }
        let event = NSEvent.mouseEvent(
            with: .leftMouseDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, eventNumber: 0, clickCount: 0, pressure: 0)!
        pins.first { $0.launcher.name == "Google Chrome" }?.mouseEntered(with: event)
        try require(pinHovered, "Pinned app hover did not expose its windows")
        print("PASS: default-right/optional-left native pin layout and pinned app hover routing")

        let provider = FeatureViewVerification.DeferredPreview()
        let peek = WindowPeekController(provider: provider, showWindows: false, automaticTicks: false)
        var entry = entries[0]
        entry.frame = CGRect(x: 100, y: 200, width: 600, height: 400)
        let source = CGRect(x: 100, y: 8, width: 160, height: 52)
        let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let pointer = CGPoint(x: 150, y: 30)
        func enter(_ time: Double, enabled: Bool = true, sourceID: String = "window") {
            peek.hover(
                entry, source: sourceID, entered: true, enabled: enabled,
                sourceFrame: source, screenFrame: screen, now: time)
        }
        enter(0)
        peek.tick(now: 0.59, pointer: pointer)
        try require(provider.calls == 0, "Peek appeared before 0.6 seconds")
        peek.tick(now: 0.6, pointer: pointer)
        try require(provider.calls == 1 && !peek.isActive, "Peek capture did not start at 0.6 seconds")
        peek.hover(
            entry, source: "window", entered: false, enabled: true, sourceFrame: source, screenFrame: screen)
        provider.completion?(.image(NSImage(size: NSSize(width: 600, height: 400))))
        try require(!peek.isActive, "Cancelled capture reopened peek")
        enter(10, sourceID: "launcher")
        peek.tick(now: 11, pointer: pointer)
        provider.completion?(.image(NSImage(size: NSSize(width: 600, height: 400))))
        try require(
            peek.activeEntry?.id == entry.id && peek.imageButton?.window?.canBecomeKey == false
                && peek.imageButton?.window?.isVisible == false, "Peek took focus or displayed during checks")
        let oldButton = peek.imageButton
        var selected: String?
        peek.onSelect = { selected = $0.id }
        peek.imageButton?.performClick(nil)
        try require(selected == entry.id && !peek.isActive, "Click did not commit peek selection")
        selected = nil
        oldButton?.performClick(nil)
        try require(selected == nil, "Dismissed peek button remained active")
        enter(20)
        peek.tick(now: 21, pointer: pointer)
        provider.completion?(.image(NSImage(size: NSSize(width: 600, height: 400))))
        peek.tick(now: 22, pointer: CGPoint(x: -100, y: -100))
        peek.tick(now: 22.2, pointer: CGPoint(x: -100, y: -100))
        try require(!peek.isActive && selected == nil, "Leaving peek selected a window or retained preview")
        enter(30, enabled: false)
        peek.tick(now: 32, pointer: pointer)
        try require(!peek.isActive, "Disabled peek activated")
        enter(40)
        peek.tick(now: 41, pointer: pointer)
        peek.retainOnly([])
        provider.completion?(.image(NSImage(size: NSSize(width: 600, height: 400))))
        try require(!peek.isActive, "Closed window's capture opened peek")
        print(
            "PASS: 0.6-second peek dwell, cancellation, launcher source, click commit, stale actions, disable and closed windows"
        )

        let parent = NSMenuItem(title: "New Window", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        parent.submenu = submenu
        var defaultOpens = 0
        let basic = ActionMenuItem("Basic") { defaultOpens += 1 }
        basic.keyEquivalent = "n"
        basic.keyEquivalentModifierMask = .command
        submenu.addItem(basic)
        submenu.addItem(ActionMenuItem("Other profile") {})
        let home = URL(fileURLWithPath: "/Users/Example User/Home's folder", isDirectory: true)
        let application = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
        var requests: [(URL, URL)] = []
        let terminal = TerminalWindowLauncher(homeDirectory: home) { requests.append(($0, $1)) }
        let commands = [terminal.newWindowItem(in: application)] + TerminalMenuDefaults.actions(from: parent)
        let menu = NSMenu()
        for command in commands { menu.addItem(command) }
        menu.performActionForItem(at: 0)
        try require(
            requests.count == 1 && requests[0].0 == home && requests[0].1 == application
                && defaultOpens == 0 && commands[0].submenu == nil
                && commands[1].submenu?.items.count == 2,
            "Terminal New Window did not target home in Terminal or lost native profiles")
        submenu.performActionForItem(at: 0)
        try require(defaultOpens == 1 && requests.count == 1, "Explicit Terminal profile stopped working")
        let unsupported = NSMenuItem(title: "New Window", action: nil, keyEquivalent: "")
        try require(
            TerminalMenuDefaults.actions(from: unsupported).isEmpty,
            "Terminal menu retained a duplicate New Window action")
        let tab = ActionMenuItem("New Tab") {}
        try require(TerminalMenuDefaults.actions(from: tab).first === tab, "Terminal New Tab was rewritten")
        print(
            "PASS: Terminal home-folder action, explicit application URL, path escaping and preserved profiles/tabs"
        )

        let windowButton = WindowButton(entry: entry)
        windowButton.updateAttention(.count(2), pulsing: true, reduceMotion: false)
        try require(
            windowButton.unreadBadge == .count(2)
                && windowButton.layer?.animation(forKey: "unreadPulse") != nil,
            "Unread badge did not pulse")
        windowButton.updateAttention(.count(2), pulsing: true, reduceMotion: true)
        try require(
            windowButton.layer?.animation(forKey: "unreadPulse") == nil && windowButton.unreadBadge != nil,
            "Reduce Motion did not keep badge steady")
        windowButton.updateAttention(nil, pulsing: false)
        try require(windowButton.unreadBadge == nil, "Disabled badge remained visible")
        print("PASS: unread badge, brief pulse, Reduce Motion and disabled attention visuals")

        let settings = SettingsWindowController(
            features: features,
            startup: LoginItemService(backend: FeatureVerification.LoginBackend(), installed: { true }),
            logDirectory: directory, decorateWindow: false)
        defer { settings.close() }
        settings.pinnedSide.selectItem(at: 1)
        settings.changePinnedSide()
        settings.peekToggle.state = .off
        settings.notificationMode.selectItem(at: 1)
        settings.changeBehavior()
        try require(
            features.preferences.value.pinnedSide == .left && !features.preferences.value.hoverPeekEnabled
                && features.preferences.value.notificationMode == .badgesOnly, "New controls did not persist")
        settings.pinnedSide.selectItem(at: 0)
        settings.changePinnedSide()
        try require(
            features.preferences.value.pinnedSide == .right && !settings.window!.isVisible
                && !panel.isVisible,
            "Right-side setting failed or checks interrupted desktop")
        print("PASS: pin side, hover peek and unread indicator settings persist without showing windows")
    }
}

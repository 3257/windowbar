import AppKit
import ApplicationServices
import WindowBarCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panels: [TaskbarPanel] = []
    private var bars: [BarView] = []
    private var statusItem: NSStatusItem?
    private var timer: Timer?
    private var edgeTimer: Timer?
    private var autoHideControllers: [BarAutoHideController] = []
    private var trackingMenus = 0
    private var switcher: WindowSwitcherController?
    private var scanning = false
    private var entries: [WindowEntry] = []
    private let scanner = DispatchQueue(label: "windowbar.accessibility", qos: .utility)
    private var allDisplays = UserDefaults.standard.bool(forKey: "allDisplays")
    private var hidden = false
    private let demo: Bool
    private let screenshots: Bool
    private var backdrop: TaskbarPanel?
    private let dock: DockReplacing
    private let windowService: WindowDiscovering
    private let windowActions: WindowActing
    private let launcherMenus: LauncherMenuProviding
    private var scanGeneration = ScanGeneration()
    private let features: FeatureCoordinator
    private let diagnostics: Diagnostics
    private let previews = HoverPreviewController()
    private lazy var shortcuts = GlobalShortcuts()
    private lazy var managementMenus = BarManagementMenus(features: features)
    private var settings: SettingsWindowController?
    private var lastTrusted: Bool?
    private var terminationSignals: [DispatchSourceSignal] = []

    init(
        demo: Bool = false, screenshots: Bool = false, dock: DockReplacing = DockController(),
        windowService: WindowDiscovering = AccessibilityWindowService(),
        windowActions: WindowActing = WindowActions(),
        launcherMenus: LauncherMenuProviding = LauncherMenuBuilder(),
        features: FeatureCoordinator = FeatureCoordinator(), diagnostics: Diagnostics = .shared
    ) {
        self.demo = demo
        self.screenshots = screenshots
        self.dock = dock
        self.windowService = windowService
        self.windowActions = windowActions
        self.launcherMenus = launcherMenus
        self.features = features
        self.diagnostics = diagnostics
        super.init()
    }
    private var replacesDock = UserDefaults.standard.object(forKey: "replacesDock") as? Bool ?? true
    private var launchers: [LauncherEntry] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        launchers = dockLaunchers()
        managementMenus.onPinsChanged = { [weak self] in self?.changePins {} }
        managementMenus.onOrderChanged = { [weak self] in self?.render() }
        managementMenus.onRefresh = { [weak self] in self?.refresh() }
        managementMenus.onError = { [weak self] _ in
            NSSound.beep()
            self?.diagnostics.record(.settingsChangeFailed)
        }
        if !demo {
            do {
                try features.preferences.importLaunchersIfNeeded(launchers)
                launchers = features.preferences.launchers()
            } catch { diagnostics.record(.scanFailed) }
            shortcuts.onAction = { [weak self] in self?.performShortcut($0) }
            do {
                try shortcuts.configure(
                    features.preferences.value.activeShortcuts)
            } catch { diagnostics.record(.shortcutRegistrationFailed) }
            for value in [SIGTERM, SIGINT, SIGHUP] {
                signal(value, SIG_IGN)
                let source = DispatchSource.makeSignalSource(signal: value, queue: .main)
                source.setEventHandler { NSApp.terminate(nil) }
                source.resume()
                terminationSignals.append(source)
            }
        }
        if !demo && replacesDock && AXIsProcessTrusted() { _ = dock.enable() }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem?.button?.image = NSImage(
            systemSymbolName: "rectangle.split.3x1", accessibilityDescription: "WindowBar")
        statusItem?.menu = makeMenu()
        if screenshots { createBackdrop() }
        previews.onSelect = { [weak self] in self?.select($0) }
        previews.onMinimize = { [weak self] in self?.minimize($0) }
        previews.onClose = { [weak self] in self?.closeWindow($0) }
        rebuildPanels()
        configureAutoHideTimer()
        NotificationCenter.default.addObserver(
            self, selector: #selector(menuBegan), name: NSMenu.didBeginTrackingNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(menuEnded), name: NSMenu.didEndTrackingNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(rebuildPanels),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(refreshAppearance),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(refresh),
            name: NSWorkspace.didActivateApplicationNotification, object: nil)
        timer = Timer.scheduledTimer(
            timeInterval: 1.5, target: self, selector: #selector(refresh), userInfo: nil, repeats: true)
        refresh()
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        edgeTimer?.invalidate()
        switcher?.dismiss()
        previews.hide()
        for source in terminationSignals { source.cancel() }
        if !demo { diagnostics.record(.shutdownRequested) }
        let restored = dock.restore()
        if !demo { diagnostics.finishSession(restoredDock: restored) }
    }

    private func createBackdrop() {
        guard let screen = NSScreen.screens.first else { return }
        let frame = NSRect(
            x: screen.visibleFrame.minX + 12, y: screen.visibleFrame.minY,
            width: screen.visibleFrame.width - 24, height: 620)
        let panel = TaskbarPanel(
            contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered,
            defer: false)
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.title = "WindowBar Screenshots"
        panel.contentView = ScreenshotBackdrop(frame: NSRect(origin: .zero, size: frame.size))
        panel.orderFrontRegardless()
        backdrop = panel
    }

    @objc private func rebuildPanels() {
        previews.hide()
        for panel in panels { panel.close() }
        panels = []
        bars = []
        autoHideControllers = []
        // The first screen is the display with the menu bar, not the focused window's display.
        let screens = allDisplays ? NSScreen.screens : Array(NSScreen.screens.prefix(1))
        for screen in screens {
            let frame = barFrame(for: screen)
            let panel = TaskbarPanel(
                contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered,
                defer: false)
            panel.isReleasedWhenClosed = false
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            panel.hidesOnDeactivate = false
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.title = "WindowBar"
            let bar = BarView(frame: NSRect(origin: .zero, size: frame.size))
            bar.onSearch = { [weak self] in self?.showSwitcher() }
            bar.onGroupToggle = { [weak self] in self?.previews.hide() }
            bar.onSelect = { [weak self] in self?.select($0) }
            bar.onMinimize = { [weak self] in self?.minimize($0) }
            bar.onClose = { [weak self] in self?.closeWindow($0) }
            bar.onLaunch = { NSWorkspace.shared.open($0.url) }
            bar.makeLauncherMenu = { [weak self] launcher, windows in
                guard let self else { return NSMenu() }
                let menu = self.launcherMenus.makeMenu(
                    launcher: launcher, windows: windows, onSelect: { [weak self] in self?.select($0) })
                self.managementMenus.augmentLauncher(menu, launcher: launcher, launchers: self.launchers)
                return menu
            }
            bar.onWindowReorder = { [weak self] source, target, after in
                self?.previews.hide()
                self?.features.moveWindow(source, relativeTo: target, after: after)
                self?.render()
            }
            bar.onLauncherReorder = { [weak self] source, target, after in
                guard let self else { return }
                self.previews.hide()
                self.changePins { try self.features.moveLauncher(source, relativeTo: target, after: after) }
            }
            bar.onHover = { [weak self] entry, button, entered in
                guard let self else { return }
                self.previews.hover(
                    entry, button: button, entered: entered,
                    mode: self.features.preferences.value.previewMode,
                    actionsEnabled: self.features.preferences.value.hoverActionsEnabled
                )
            }
            bar.onDragStart = { [weak self] in self?.previews.hide() }
            bar.augmentWindowMenu = { [weak self] menu, entry in
                guard let self else { return }
                self.managementMenus.augmentWindow(menu, entry: entry, entries: self.entries)
            }
            bar.menuButton.target = self
            bar.menuButton.action = #selector(showMenu(_:))
            bar.permissionButton.target = self
            bar.permissionButton.action = #selector(enableAccessibility)
            panel.contentView = bar
            panels.append(panel)
            bars.append(bar)
            let autoHide = BarAutoHideController()
            autoHide.layout(shownFrame: frame, screenFrame: screen.frame, panel: panel)
            autoHideControllers.append(autoHide)
            if !hidden { panel.orderFrontRegardless() }
        }
        render()
    }

    private func barFrame(for screen: NSScreen) -> NSRect {
        let visible = screen.visibleFrame
        let bottom = dock.isEnabled && !demo ? screen.frame.minY : visible.minY
        let width = max(200, visible.width - 24)
        return NSRect(x: visible.minX + 12, y: bottom + 8, width: width, height: BarLayout.height)
    }

    @objc private func refresh() {
        // Dock size/auto-hide changes need no relaunch.
        let screens = allDisplays ? NSScreen.screens : Array(NSScreen.screens.prefix(1))
        for (index, screen) in screens.enumerated() where panels.indices.contains(index) {
            autoHideControllers[index].layout(
                shownFrame: barFrame(for: screen), screenFrame: screen.frame, panel: panels[index])
        }
        if demo {
            entries = sampleWindows()
            render()
            return
        }
        let trusted = AXIsProcessTrusted()
        if lastTrusted != trusted {
            lastTrusted = trusted
            diagnostics.record(.permissionChanged)
        }
        guard trusted else {
            scanGeneration.invalidate()
            _ = dock.restore()
            entries = []
            render()
            return
        }
        if replacesDock && !hidden { _ = dock.enable() }
        guard !scanning else { return }
        scanning = true
        let captured = scanGeneration.value
        let service = windowService
        scanner.async { [weak self] in
            let windows = service.readWindows()
            DispatchQueue.main.async {
                guard let self else { return }
                self.scanning = false
                guard self.scanGeneration.accepts(captured) else {
                    self.refresh()
                    return
                }
                self.entries = windows
                self.render()
            }
        }
    }

    private func render() {
        entries = features.ordered(entries)
        previews.retainOnly(Set(entries.map(\.id)))
        let trusted = demo || AXIsProcessTrusted()
        let screens = allDisplays ? NSScreen.screens : Array(NSScreen.screens.prefix(1))
        for (index, screen) in screens.enumerated() where panels.indices.contains(index) {
            autoHideControllers[index].layout(
                shownFrame: barFrame(for: screen), screenFrame: screen.frame, panel: panels[index])
        }
        switcher?.update(entries: entries, preferences: features.preferences.value)
        updateAutoHide()
        let displays = NSScreen.screens.map { DisplayRegion(id: displayID($0), frame: $0.frame) }
        for (bar, screen) in zip(bars, screens) {
            let visible = features.visible(entries, displayID: displayID(screen), displays: displays)
            bar.update(
                entries: visible, trusted: trusted, launchers: launchers,
                preferences: features.preferences.value)
        }
    }

    private func select(_ entry: WindowEntry) {
        guard demo || entry.element != nil else { return }
        previews.hide()
        switcher?.dismiss()
        scanGeneration.invalidate()
        entries = entries.map { existing in
            var updated = existing
            updated.focused = existing.id == entry.id
            return updated
        }
        render()
        for bar in bars { bar.revealWindow(entry.id) }
        if demo { return }
        windowActions.select(entry) { [weak self] in self?.refresh() }
    }

    private func minimize(_ entry: WindowEntry) {
        scanGeneration.invalidate()
        if entry.minimized {
            select(entry)
        } else {
            windowActions.minimize(entry)
            refresh()
        }
    }

    private func closeWindow(_ entry: WindowEntry) {
        scanGeneration.invalidate()
        windowActions.close(entry)
        refresh()
    }

    @objc private func enableAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        if let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        {
            NSWorkspace.shared.open(url)
        }
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        let title = NSMenuItem(title: demo ? "WindowBar · Demo" : "WindowBar", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        menu.addItem(.separator())
        let items: [(String, Selector, String)] = [
            (hidden ? "Show bar" : "Hide bar", #selector(toggleVisibility), ""),
            ("Replace macOS Dock", #selector(toggleDock), ""),
            ("Show on all displays", #selector(toggleDisplays), ""),
            ("Search windows…", #selector(showSwitcher), ""),
            ("Settings…", #selector(showSettings), ","),
            ("Open Downloads", #selector(openDownloads), ""),
            ("Open Trash", #selector(openTrash), ""),
            ("Refresh windows", #selector(refresh), ""),
            ("Enable Accessibility…", #selector(enableAccessibility), ""),
            ("Quit WindowBar", #selector(quit), "q"),
        ]
        for (title, action, shortcut) in items {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: shortcut)
            item.target = self
            if action == #selector(showSwitcher) { item.isEnabled = features.preferences.value.searchEnabled }
            if action == #selector(toggleDisplays) { item.state = allDisplays ? .on : .off }
            if action == #selector(toggleDock) { item.state = replacesDock ? .on : .off }
            menu.addItem(item)
        }
        return menu
    }

    @objc private func showMenu(_ sender: NSButton) {
        makeMenu().popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.maxY + 8), in: sender)
    }

    @objc private func toggleVisibility() {
        previews.hide()
        hidden.toggle()
        configureAutoHideTimer()
        if hidden {
            dock.restore()
        } else if replacesDock && !demo && AXIsProcessTrusted() {
            _ = dock.enable()
        }
        for panel in panels { if hidden { panel.orderOut(nil) } else { panel.orderFrontRegardless() } }
        statusItem?.menu = makeMenu()
    }

    @objc private func toggleDock() {
        replacesDock.toggle()
        if replacesDock && !hidden && !demo && AXIsProcessTrusted() {
            _ = dock.enable()
        } else {
            dock.restore()
        }
        UserDefaults.standard.set(replacesDock, forKey: "replacesDock")
        refresh()
        statusItem?.menu = makeMenu()
    }

    @objc private func openDownloads() {
        if let url = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func openTrash() {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash")
        NSWorkspace.shared.open(url)
    }

    @objc private func toggleDisplays() {
        allDisplays.toggle()
        UserDefaults.standard.set(allDisplays, forKey: "allDisplays")
        rebuildPanels()
        statusItem?.menu = makeMenu()
    }

    @objc private func quit() { NSApp.terminate(nil) }

    private func displayID(_ screen: NSScreen) -> UInt32 {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
            ?? CGMainDisplayID()
    }

    @objc private func refreshAppearance() {
        previews.hide()
        rebuildPanels()
    }

    @objc private func showSettings() {
        previews.hide()
        if settings == nil {
            let controller = SettingsWindowController(features: features)
            controller.onPreferencesChanged = { [weak self] updated in
                guard let self else { return }
                let previous = self.features.preferences.value
                if !self.demo {
                    try self.shortcuts.configure(updated.activeShortcuts)
                }
                do { try self.features.preferences.save(updated) } catch {
                    if !self.demo {
                        try? self.shortcuts.configure(previous.activeShortcuts)
                    }
                    throw error
                }
                self.previews.hide()
                self.configureAutoHideTimer()
                self.launchers = self.features.preferences.launchers()
                self.render()
                self.statusItem?.menu = self.makeMenu()
                if !self.demo {
                    self.diagnostics.record(
                        previous.shortcuts == updated.shortcuts
                            && previous.shortcutsEnabled == updated.shortcutsEnabled
                            ? .preferencesChanged : .shortcutsChanged)
                }
            }
            controller.onError = { [weak self] _ in self?.diagnostics.record(.settingsChangeFailed) }
            settings = controller
        }
        settings?.present()
    }

    @objc private func showSwitcher() {
        guard features.preferences.value.searchEnabled else { return }
        previews.hide()
        let previousApp = NSWorkspace.shared.frontmostApplication
        if switcher == nil { switcher = WindowSwitcherController() }
        switcher?.onSelect = { [weak self] in self?.select($0) }
        switcher?.onCancel = {
            if NSWorkspace.shared.frontmostApplication?.processIdentifier
                == ProcessInfo.processInfo.processIdentifier
            {
                previousApp?.activate(options: [])
            }
        }
        switcher?.update(entries: entries, preferences: features.preferences.value)
        switcher?.present()
    }

    @objc private func menuBegan() { trackingMenus += 1 }
    @objc private func menuEnded() { trackingMenus = max(0, trackingMenus - 1) }

    private func configureAutoHideTimer() {
        edgeTimer?.invalidate()
        edgeTimer = nil
        guard features.preferences.value.autoHideEnabled, !hidden else { return }
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in self?.updateAutoHide() }
        edgeTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func updateAutoHide() {
        guard !hidden else { return }
        let value = features.preferences.value
        let point = NSEvent.mouseLocation
        for (panel, controller) in zip(panels, autoHideControllers) {
            let interacting =
                trackingMenus > 0 || settings?.window?.isVisible == true
                || switcher?.window?.isVisible == true
                || previews.interactionFrame?.contains(point) == true
                || (!controller.hidden && NSEvent.pressedMouseButtons != 0)
            controller.update(
                panel: panel, enabled: value.autoHideEnabled, delay: value.autoHideDelay,
                pointer: point, interaction: interacting, now: ProcessInfo.processInfo.systemUptime)
        }
    }

    private func changePins(_ change: () throws -> Void) {
        do {
            try change()
            launchers = features.preferences.launchers()
            render()
            settings?.refresh()
        } catch { NSSound.beep() }
    }

    private func performShortcut(_ action: ShortcutAction) {
        if action == .searchWindows {
            showSwitcher()
            return
        }
        if let index = action.pinnedIndex {
            guard launchers.indices.contains(index) else { return }
            NSWorkspace.shared.open(launchers[index].url)
            return
        }
        let regions = NSScreen.screens.map { DisplayRegion(id: displayID($0), frame: $0.frame) }
        let screenID =
            entries.first(where: \.focused).flatMap {
                DisplayFilter.displayID(for: $0.frame, displays: regions)
            }
            ?? NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }).map {
                displayID($0)
            }
            ?? CGMainDisplayID()
        let visible = features.navigationEntries(
            features.visible(entries, displayID: screenID, displays: regions))
        guard
            let index = ShortcutBinding.cycleIndex(
                count: visible.count, focusedIndex: visible.firstIndex(where: \.focused),
                forward: action == .nextWindow)
        else { return }
        select(visible[index])
    }
}

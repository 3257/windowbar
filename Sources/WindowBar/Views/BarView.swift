import AppKit
import QuartzCore
import WindowBarCore

final class BarView: NSVisualEffectView {
    let launchScroll = HorizontalScrollView()
    let launchDocument = NSView()
    let scroll = HorizontalScrollView()
    let document = NSView()
    let menuButton = NSButton()
    let searchButton = NSButton()
    private var preferences = BarPreferences()
    private var groups: [WindowGroup] = []
    private var groupButtons: [String: WindowGroupButton] = [:]
    private var collapsedGroups = Set<String>()
    private var displayViews: [NSView] = []
    private var displayFocus: [Bool] = []
    let permissionButton = NSButton(title: "Enable Accessibility", target: nil, action: nil)
    let message = NSTextField(labelWithString: "")
    private let divider = NSBox()
    private var buttons: [String: WindowButton] = [:]
    private var entries: [WindowEntry] = []
    private var launchers: [LauncherEntry] = []
    private var launcherButtons: [String: LauncherButton] = [:]
    private var trusted = false
    var onSearch: (() -> Void)?
    var onGroupToggle: (() -> Void)?
    var onSelect: ((WindowEntry) -> Void)?
    var onMinimize: ((WindowEntry) -> Void)?
    var onClose: ((WindowEntry) -> Void)?
    var onLaunch: ((LauncherEntry) -> Void)?
    var makeLauncherMenu: ((LauncherEntry, [WindowEntry]) -> NSMenu)?
    var onWindowReorder: ((String, String, Bool) -> Void)?
    var onLauncherReorder: ((String, String, Bool) -> Void)?
    var onLauncherHover: ((LauncherEntry, [WindowEntry], LauncherButton, Bool) -> Void)?
    var onHover: ((WindowEntry, WindowButton, Bool) -> Void)?
    var onDragStart: (() -> Void)?
    var augmentWindowMenu: ((NSMenu, WindowEntry) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        material = .popover
        blendingMode = .behindWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 16
        layer?.borderWidth = 1
        divider.boxType = .separator
        addSubview(divider)
        updateAppearance()
        launchScroll.drawsBackground = false
        launchScroll.hasHorizontalScroller = false
        launchScroll.hasVerticalScroller = false
        launchScroll.documentView = launchDocument
        addSubview(launchScroll)
        scroll.drawsBackground = false
        scroll.hasHorizontalScroller = false
        scroll.hasVerticalScroller = false
        scroll.documentView = document
        addSubview(scroll)
        menuButton.image = NSImage(systemSymbolName: "ellipsis", accessibilityDescription: "WindowBar menu")
        menuButton.contentTintColor = .secondaryLabelColor
        menuButton.isBordered = false
        menuButton.toolTip = "WindowBar settings"
        addSubview(menuButton)
        searchButton.image = NSImage(
            systemSymbolName: "magnifyingglass", accessibilityDescription: "Search windows")
        searchButton.isBordered = false
        searchButton.toolTip = "Search windows"
        searchButton.target = self
        searchButton.action = #selector(searchWindows)
        addSubview(searchButton)
        permissionButton.bezelStyle = .rounded
        permissionButton.contentTintColor = accent
        addSubview(permissionButton)
        message.font = .systemFont(ofSize: 12)
        message.textColor = .secondaryLabelColor
        addSubview(message)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(
        entries: [WindowEntry], trusted: Bool, launchers: [LauncherEntry] = [],
        preferences: BarPreferences = BarPreferences()
    ) {
        if self.preferences.groupingMode != preferences.groupingMode { collapsedGroups.removeAll() }
        self.preferences = preferences
        searchButton.isHidden = !preferences.searchEnabled
        self.entries = entries
        self.launchers = launchers
        self.trusted = trusted
        let launcherKeys = Set(launchers.map { $0.url.path })
        for key in Array(launcherButtons.keys) where !launcherKeys.contains(key) {
            launcherButtons.removeValue(forKey: key)?.removeFromSuperview()
        }
        for launcher in launchers where launcherButtons[launcher.url.path] == nil {
            let button = LauncherButton(launcher)
            button.onHover = { [weak self] in self?.onLauncherHover?($0, $1, $2, $3) }
            button.onDismissHover = { [weak self] in self?.onDragStart?() }
            button.onLaunch = { [weak self] in self?.onLaunch?($0) }
            button.makeContextMenu = { [weak self] launcher, windows in
                self?.makeLauncherMenu?(launcher, windows) ?? NSMenu()
            }
            button.onReorder = { [weak self] in self?.onLauncherReorder?($0, $1, $2) }
            button.onDragStart = { [weak self] in self?.onDragStart?() }
            launcherButtons[launcher.url.path] = button
            launchDocument.addSubview(button)
        }
        for launcher in launchers {
            let identifier = Bundle(url: launcher.url)?.bundleIdentifier
            let pids = Set(
                identifier.map {
                    NSRunningApplication.runningApplications(withBundleIdentifier: $0).map(
                        \.processIdentifier)
                } ?? [])
            launcherButtons[launcher.url.path]?.windows = entries.filter {
                pids.contains($0.pid) || ($0.element == nil && $0.appName == launcher.name)
            }
        }
        let keys = Set(entries.map(\.id))
        for key in Array(buttons.keys) where !keys.contains(key) {
            buttons.removeValue(forKey: key)?.removeFromSuperview()
        }
        var windowNumbers: [String: Int] = [:]
        for entry in entries {
            let button: WindowButton
            if let existing = buttons[entry.id] {
                button = existing
                button.update(entry)
            } else {
                button = WindowButton(entry: entry)
                button.onSelect = { [weak self] in self?.onSelect?($0) }
                button.onMinimize = { [weak self] in self?.onMinimize?($0) }
                button.onClose = { [weak self] in self?.onClose?($0) }
                button.onReorder = { [weak self] in self?.onWindowReorder?($0, $1, $2) }
                button.onHover = { [weak self] in self?.onHover?($0, $1, $2) }
                button.onDismissHover = { [weak self] in self?.onDragStart?() }
                button.onDragStart = { [weak self] in self?.onDragStart?() }
                button.augmentMenu = { [weak self] in self?.augmentWindowMenu?($0, $1) }
                buttons[entry.id] = button
                document.addSubview(button)
            }
            let group = entry.pid == 0 ? entry.appName : String(entry.pid)
            windowNumbers[group, default: 0] += 1
            button.windowNumber = windowNumbers[group, default: 1]
            if onHover != nil { button.toolTip = nil }
        }
        rebuildGroups()
        permissionButton.isHidden = trusted
        scroll.isHidden = !trusted || entries.isEmpty
        message.isHidden = trusted && !entries.isEmpty
        message.stringValue =
            trusted ? "Open an app window to see it here." : "See each window. Switch with one click."
        needsLayout = true
        needsDisplay = true
    }

    func updateAttention(
        _ attention: AppAttention, mode: BarPreferences.NotificationMode,
        now: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) {
        for button in buttons.values {
            let id = button.entry.appIdentity
            button.updateAttention(
                mode == .off ? nil : attention.badges[id],
                pulsing: mode == .badgesAndPulse && attention.isPulsing(id, now: now))
        }
        for button in launcherButtons.values {
            let id = Bundle(url: button.launcher.url)?.bundleIdentifier ?? ""
            button.updateAttention(
                mode == .off ? nil : attention.badges[id],
                pulsing: mode == .badgesAndPulse && attention.isPulsing(id, now: now))
        }
    }

    override func layout() {
        super.layout()
        let shelf = ShelfLayout(
            width: bounds.width, pinnedCount: launchers.count,
            searchEnabled: preferences.searchEnabled, side: preferences.pinnedSide)
        let launcherWidth = shelf.launcherWidth
        let left = CGFloat(shelf.windowX)
        searchButton.frame = NSRect(x: 12, y: bounds.height / 2 - 16, width: 26, height: 32)
        let middle = bounds.height / 2
        let launcherX = shelf.launcherX
        launchScroll.frame = NSRect(x: launcherX, y: middle - 18, width: launcherWidth, height: 36)
        divider.isHidden = launchers.isEmpty
        divider.frame = NSRect(x: shelf.dividerX, y: 16, width: 1, height: bounds.height - 32)
        launchDocument.frame = NSRect(x: 0, y: 0, width: CGFloat(launchers.count) * 38, height: 36)
        for (index, launcher) in launchers.enumerated() {
            launcherButtons[launcher.url.path]?.frame = NSRect(
                x: CGFloat(index) * 38, y: 2, width: 32, height: 32)
        }
        menuButton.frame = NSRect(x: bounds.width - 42, y: middle - 16, width: 28, height: 32)
        scroll.frame = NSRect(
            x: left, y: 7,
            width: shelf.windowWidth,
            height: bounds.height - 14)
        let geometry = BarLayout(availableWidth: Double(scroll.bounds.width), focused: displayFocus)
        let oldX = scroll.contentView.bounds.minX
        document.frame = NSRect(x: 0, y: 0, width: geometry.documentWidth, height: scroll.bounds.height)
        NSAnimationContext.runAnimationGroup { context in
            let animate =
                window?.isVisible == true && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            context.duration = animate ? 0.22 : 0
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            for (button, position) in zip(displayViews, geometry.buttons) {
                let frame = NSRect(x: position.x, y: 0, width: position.width, height: BarLayout.buttonHeight)
                do {
                    if !animate || button.frame.isEmpty {
                        button.frame = frame
                    } else if button.frame != frame {
                        button.animator().frame = frame
                    }
                    button.needsDisplay = true
                }
            }
        }
        scroll.contentView.scroll(
            to: NSPoint(x: min(oldX, max(0, document.frame.width - scroll.bounds.width)), y: 0))
        permissionButton.frame = NSRect(
            x: max(left, scroll.frame.maxX - 166), y: middle - 15, width: min(156, scroll.bounds.width),
            height: 30)
        message.frame = NSRect(
            x: left + 10, y: middle - 9, width: max(0, scroll.bounds.width - (trusted ? 20 : 180)), height: 18
        )
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    private func updateAppearance() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.borderColor = NSColor.separatorColor.cgColor
            if NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency {
                layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
                blendingMode = .withinWindow
            } else {
                layer?.backgroundColor = nil
                blendingMode = .behindWindow
            }
        }
        needsDisplay = true
    }

    func revealWindow(_ id: String) {
        guard let button = buttons[id] else { return }
        if let group = groups.first(where: { $0.windowIDs.contains(id) }),
            collapsedGroups.remove(group.key) != nil
        {
            rebuildGroups()
            needsLayout = true
            layoutSubtreeIfNeeded()
        }
        document.scrollToVisible(button.frame)
    }

    @objc private func searchWindows() { onSearch?() }

    private func rebuildGroups() {
        groups = WindowGrouping.groups(entries.map(\.groupingIdentity), mode: preferences.groupingMode)
        let keys = Set(groups.map(\.key))
        collapsedGroups.formIntersection(keys)
        for key in Array(groupButtons.keys) where !keys.contains(key) {
            groupButtons.removeValue(forKey: key)?.removeFromSuperview()
        }
        displayViews = []
        displayFocus = []
        for button in buttons.values { button.isHidden = true }
        if preferences.groupingMode == .none {
            for entry in entries {
                if let button = buttons[entry.id] {
                    button.isHidden = false
                    displayViews.append(button)
                    displayFocus.append(entry.focused)
                }
            }
            return
        }
        let byID = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
        for group in groups {
            let button = groupButtons[group.key] ?? WindowGroupButton()
            groupButtons[group.key] = button
            if button.superview == nil { document.addSubview(button) }
            let collapsed = collapsedGroups.contains(group.key)
            let focused = group.windowIDs.contains { byID[$0]?.focused == true }
            let label =
                preferences.groupingMode == .appAndProfile
                ? group.windowIDs.first.flatMap { byID[$0]?.profile?.name } ?? group.title : group.title
            button.title = "\(collapsed ? "▸" : "▾") \(label) · \(group.windowIDs.count)"
            button.toolTip =
                "\(collapsed ? "Expand" : "Collapse") \(group.title), \(group.windowIDs.count) windows"
            button.setAccessibilityLabel(button.toolTip)
            button.contentTintColor = focused ? accent : .secondaryLabelColor
            button.onToggle = { [weak self] in
                guard let self else { return }
                if !self.collapsedGroups.insert(group.key).inserted { self.collapsedGroups.remove(group.key) }
                self.onGroupToggle?()
                self.rebuildGroups()
                self.needsLayout = true
            }
            displayViews.append(button)
            displayFocus.append(collapsed && focused)
            if !collapsed {
                for id in group.windowIDs {
                    guard let window = buttons[id] else { continue }
                    window.isHidden = false
                    displayViews.append(window)
                    displayFocus.append(window.entry.focused)
                }
            }
        }
    }
}

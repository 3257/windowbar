import AppKit
import ApplicationServices
import QuartzCore

// Preserve the user's Dock preferences, and restore them even after an unexpected exit.
final class DockController {
    static let backupURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/WindowBar/dock-backup.plist")
    private var token: String?

    @discardableResult private static func run(_ path: String, _ arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run(); process.waitUntilExit(); return process.terminationStatus == 0 }
        catch { return false }
    }

    static func readBackup() -> [String: Any]? {
        guard let data = try? Data(contentsOf: backupURL) else { return nil }
        return (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any]
    }

    @discardableResult static func restore(_ backup: [String: Any]) -> Bool {
        var succeeded = true
        for key in ["autohide", "autohide-delay"] {
            if let value = backup[key] as? NSNumber {
                let arguments = key == "autohide"
                    ? ["write", "com.apple.dock", key, "-bool", value.boolValue ? "true" : "false"]
                    : ["write", "com.apple.dock", key, "-float", value.stringValue]
                succeeded = run("/usr/bin/defaults", arguments) && succeeded
            } else {
                let removed = run("/usr/bin/defaults", ["delete", "com.apple.dock", key])
                CFPreferencesAppSynchronize("com.apple.dock" as CFString)
                succeeded = (removed || CFPreferencesCopyAppValue(key as CFString, "com.apple.dock" as CFString) == nil) && succeeded
            }
        }
        if succeeded {
            try? FileManager.default.removeItem(at: backupURL)
            _ = run("/usr/bin/killall", ["Dock"])
        }
        return succeeded
    }

    func enable() -> Bool {
        if token != nil { return true }
        if let previous = Self.readBackup() {
            let owner = previous["pid"] as? Int32 ?? 0
            // Another live WindowBar instance must retain ownership of its backup.
            if owner > 0 && kill(owner, 0) == 0 { return false }
            guard Self.restore(previous) else { return false }
        }
        let newToken = UUID().uuidString
        var backup: [String: Any] = ["token": newToken, "pid": getpid()]
        CFPreferencesAppSynchronize("com.apple.dock" as CFString)
        for key in ["autohide", "autohide-delay"] {
            if let value = CFPreferencesCopyAppValue(key as CFString, "com.apple.dock" as CFString) {
                backup[key] = value
            }
        }
        do {
            try FileManager.default.createDirectory(at: Self.backupURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try PropertyListSerialization.data(fromPropertyList: backup, format: .xml, options: 0)
            try data.write(to: Self.backupURL, options: .atomic)
            let guardProcess = Process()
            guardProcess.executableURL = Bundle.main.executableURL
            guardProcess.arguments = ["--dock-guard", String(getpid()), newToken]
            guardProcess.standardOutput = FileHandle.nullDevice
            guardProcess.standardError = FileHandle.nullDevice
            try guardProcess.run()
        } catch {
            _ = Self.restore(backup)
            return false
        }
        token = newToken
        guard Self.run("/usr/bin/defaults", ["write", "com.apple.dock", "autohide", "-bool", "true"]),
              Self.run("/usr/bin/defaults", ["write", "com.apple.dock", "autohide-delay", "-float", "3600"]) else {
            restore(); return false
        }
        _ = Self.run("/usr/bin/killall", ["Dock"])
        return true
    }

    func restore() {
        guard let token, let backup = Self.readBackup(), backup["token"] as? String == token else { return }
        if Self.restore(backup) { self.token = nil }
    }

    static func watch(pid: pid_t, token: String) {
        while let backup = readBackup(), backup["token"] as? String == token {
            if kill(pid, 0) != 0 { _ = restore(backup); return }
            Thread.sleep(forTimeInterval: 1)
        }
    }
}

struct LauncherEntry {
    let url: URL
    let name: String
    let icon: NSImage
}

func dockLaunchers() -> [LauncherEntry] {
    var launchers: [LauncherEntry] = []
    var seen = Set<String>()
    let finder = URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")
    func append(_ url: URL, name: String) {
        guard FileManager.default.fileExists(atPath: url.path), seen.insert(url.standardizedFileURL.path).inserted else { return }
        launchers.append(LauncherEntry(url: url, name: name, icon: NSWorkspace.shared.icon(forFile: url.path)))
    }
    append(finder, name: "Finder")
    let tiles = CFPreferencesCopyAppValue("persistent-apps" as CFString, "com.apple.dock" as CFString) as? [[String: Any]] ?? []
    for tile in tiles {
        guard let data = tile["tile-data"] as? [String: Any], let file = data["file-data"] as? [String: Any],
              let string = file["_CFURLString"] as? String, let url = URL(string: string), url.isFileURL else { continue }
        append(url, name: data["file-label"] as? String ?? url.deletingPathExtension().lastPathComponent)
    }
    return launchers
}

// WindowBar uses public Accessibility APIs. No screen capture or private Dock APIs.
struct WindowEntry {
    let id: String
    let pid: pid_t
    let appName: String
    let title: String
    let icon: NSImage?
    let element: AXUIElement?
    let minimized: Bool
    var focused: Bool
}

func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
    return value
}

func readWindows() -> [WindowEntry] {
    guard AXIsProcessTrusted() else { return [] }
    let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
    var result: [WindowEntry] = []
    for app in NSWorkspace.shared.runningApplications where
        app.activationPolicy == .regular && app.processIdentifier != getpid() && !app.isTerminated {
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(appElement, 0.15)
        guard let windows = attribute(appElement, kAXWindowsAttribute) as? [AXUIElement] else { continue }
        let focusedValue = attribute(appElement, kAXFocusedWindowAttribute)
        for (index, window) in windows.enumerated() {
            AXUIElementSetMessagingTimeout(window, 0.15)
            let role = attribute(window, kAXRoleAttribute) as? String
            guard role == kAXWindowRole else { continue }
            let subrole = attribute(window, kAXSubroleAttribute) as? String
            guard subrole != kAXSystemDialogSubrole else { continue }
            let rawTitle = (attribute(window, kAXTitleAttribute) as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let minimized = (attribute(window, kAXMinimizedAttribute) as? Bool) ?? false
            let focused = app.processIdentifier == frontPID && focusedValue.map { CFEqual($0, window) } == true
            result.append(WindowEntry(
                id: "\(app.processIdentifier):\(CFHash(window))", pid: app.processIdentifier,
                appName: app.localizedName ?? "App", title: rawTitle?.isEmpty == false ? rawTitle! : "Window \(index + 1)",
                icon: app.icon, element: window, minimized: minimized, focused: focused
            ))
        }
    }
    return result.sorted {
        let comparison = $0.appName.localizedCaseInsensitiveCompare($1.appName)
        return comparison == .orderedSame ? $0.id < $1.id : comparison == .orderedAscending
    }
}

func sampleWindows() -> [WindowEntry] {
    let specs: [(String, String, Bool, Bool)] = [
        ("Google Chrome", "Project dashboard", false, true),
        ("Google Chrome", "Research & references", false, false),
        ("Google Chrome", "Personal", true, false),
        ("Terminal", "windowbar — zsh", false, false),
        ("Terminal", "Local dev server", false, false)
    ]
    return specs.enumerated().map { index, spec in
        let path = spec.0 == "Terminal" ? "/System/Applications/Utilities/Terminal.app" : "/Applications/Google Chrome.app"
        return WindowEntry(id: "demo-\(index)", pid: 0, appName: spec.0, title: spec.1,
                           icon: NSWorkspace.shared.icon(forFile: path), element: nil, minimized: spec.2, focused: spec.3)
    }
}

final class TaskbarPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class HorizontalScrollView: NSScrollView {
    override func scrollWheel(with event: NSEvent) {
        guard let documentView else { return }
        let delta = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) ? event.scrollingDeltaX : event.scrollingDeltaY
        let multiplier: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 16
        let maxX = max(0, documentView.frame.width - contentView.bounds.width)
        let x = min(maxX, max(0, contentView.bounds.minX - delta * multiplier))
        contentView.scroll(to: NSPoint(x: x, y: 0))
        reflectScrolledClipView(contentView)
    }
}

let accent = NSColor(calibratedRed: 0.43, green: 0.68, blue: 1, alpha: 1)

func drawText(_ text: String, in rect: NSRect, size: CGFloat, weight: NSFont.Weight, color: NSColor) {
    let style = NSMutableParagraphStyle()
    style.lineBreakMode = .byTruncatingTail
    NSAttributedString(string: text, attributes: [
        .font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color, .paragraphStyle: style
    ]).draw(in: rect)
}

final class WindowButton: NSButton {
    var entry: WindowEntry
    var windowNumber = 1
    var onSelect: ((WindowEntry) -> Void)?
    var onMinimize: ((WindowEntry) -> Void)?
    var onClose: ((WindowEntry) -> Void)?
    @objc dynamic var focusAmount: CGFloat = 0 { didSet { needsDisplay = true } }
    @objc dynamic var hoverAmount: CGFloat = 0 { didSet { needsDisplay = true } }
    private var hoverArea: NSTrackingArea?
    override var isFlipped: Bool { true }

    init(entry: WindowEntry) {
        self.entry = entry
        super.init(frame: .zero)
        isBordered = false
        title = ""
        target = self
        action = #selector(selectWindow)
        update(entry)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override class func defaultAnimation(forKey key: NSAnimatablePropertyKey) -> Any? {
        if key == "focusAmount" || key == "hoverAmount" { return CABasicAnimation() }
        return super.defaultAnimation(forKey: key)
    }

    func update(_ entry: WindowEntry) {
        let focusChanged = self.entry.focused != entry.focused
        self.entry = entry
        let target: CGFloat = entry.focused ? 1 : 0
        if frame.isEmpty || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            focusAmount = target
        } else if focusChanged {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.22
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                animator().focusAmount = target
            }
        }
        toolTip = "\(entry.appName) — \(entry.title)\(entry.minimized ? " (minimized)" : "")"
        setAccessibilityLabel(toolTip)
        needsDisplay = true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area)
        hoverArea = area
    }

    private func hover(_ amount: CGFloat) {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { hoverAmount = amount; return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.14
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().hoverAmount = amount
        }
    }
    override func mouseEntered(with event: NSEvent) { hover(1) }
    override func mouseExited(with event: NSEvent) { hover(0) }

    override func draw(_ dirtyRect: NSRect) {
        let box = bounds.insetBy(dx: 1, dy: 1)
        let path = NSBezierPath(roundedRect: box, xRadius: 10, yRadius: 10)
        let focus = min(1, max(0, focusAmount))
        let hover = min(1, max(0, hoverAmount))
        let fill = NSColor.white.withAlphaComponent(0.055 + hover * 0.075)
            .blended(withFraction: focus, of: accent.withAlphaComponent(0.32 + hover * 0.08))!
        fill.setFill()
        path.fill()
        NSColor.white.withAlphaComponent(0.075 + hover * 0.125).blended(withFraction: focus, of: accent)!.setStroke()
        path.lineWidth = 1 + focus * 0.8
        path.stroke()
        let iconOnly = bounds.width < 76
        let compact = bounds.width < 140
        let iconSize: CGFloat = compact ? 22 : 27
        let iconX: CGFloat = iconOnly ? (bounds.width - iconSize) / 2 : (compact ? 8 : 11)
        let iconY: CGFloat = iconOnly ? 7 : (bounds.height - iconSize) / 2
        entry.icon?.draw(in: NSRect(x: iconX, y: iconY, width: iconSize, height: iconSize), from: .zero,
                         operation: .sourceOver, fraction: entry.minimized ? 0.5 : 1, respectFlipped: true, hints: nil)
        if iconOnly {
            let style = NSMutableParagraphStyle()
            style.alignment = .center
            NSAttributedString(string: String(windowNumber), attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .medium),
                .foregroundColor: entry.focused ? accent : NSColor.secondaryLabelColor,
                .paragraphStyle: style
            ]).draw(in: NSRect(x: 0, y: 32, width: bounds.width, height: 15))
        } else {
            let textX: CGFloat = compact ? 36 : 48
            let subtitle = bounds.width >= 112
            drawText(entry.title, in: NSRect(x: textX, y: subtitle ? 9 : 18, width: max(0, bounds.width - textX - 8), height: 18),
                     size: compact ? 11 : 12, weight: .medium, color: entry.minimized ? .secondaryLabelColor : .labelColor)
            if subtitle {
                drawText(entry.appName + (entry.minimized ? " · Minimized" : ""),
                         in: NSRect(x: textX, y: 29, width: max(0, bounds.width - textX - 8), height: 15),
                         size: 10, weight: .regular, color: entry.focused ? accent : .secondaryLabelColor)
            }
        }
        if focus > 0.001 {
            accent.withAlphaComponent(focus).setFill()
            let indicatorWidth = min(48, bounds.width - 16)
            NSBezierPath(roundedRect: NSRect(x: (bounds.width - indicatorWidth) / 2, y: bounds.height - 5,
                                          width: indicatorWidth, height: 3), xRadius: 1.5, yRadius: 1.5).fill()
        }
    }

    @objc private func selectWindow() { onSelect?(entry) }
    @objc private func minimizeWindow() { onMinimize?(entry) }
    @objc private func closeWindow() { onClose?(entry) }

    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu()
        let heading = NSMenuItem(title: entry.appName, action: nil, keyEquivalent: "")
        heading.isEnabled = false
        menu.addItem(heading)
        menu.addItem(.separator())
        for (title, action) in [("Switch to window", #selector(selectWindow)),
                                (entry.minimized ? "Restore window" : "Minimize window", #selector(minimizeWindow)),
                                ("Close window", #selector(closeWindow))] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }
}

final class BrandView: NSView {
    var windowCount = 0
    var appCount = 0
    var trusted = false
    override func draw(_ dirtyRect: NSRect) {
        let y = (bounds.height - 30) / 2
        accent.withAlphaComponent(0.18).setFill()
        NSBezierPath(roundedRect: NSRect(x: 0, y: y, width: 30, height: 30), xRadius: 8, yRadius: 8).fill()
        drawText("W", in: NSRect(x: 6, y: y + 4, width: 22, height: 22), size: 17, weight: .bold, color: accent)
        if bounds.width > 40 {
            drawText("WINDOWBAR", in: NSRect(x: 40, y: 34, width: 115, height: 16), size: 10, weight: .bold, color: .labelColor)
            drawText(trusted ? "\(windowCount) windows · \(appCount) apps" : "One click to your window",
                     in: NSRect(x: 40, y: 17, width: 116, height: 14), size: 9, weight: .regular, color: .secondaryLabelColor)
        }
    }
}

final class ActionMenuItem: NSMenuItem {
    private let handler: () -> Void
    init(_ title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(performAction), keyEquivalent: "")
        target = self
    }
    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func performAction() { handler() }
}

final class LauncherButton: NSButton {
    let launcher: LauncherEntry
    var windows: [WindowEntry] = []
    var onSelect: ((WindowEntry) -> Void)?
    init(_ launcher: LauncherEntry) {
        self.launcher = launcher
        super.init(frame: .zero)
        image = launcher.icon
        imageScaling = .scaleProportionallyDown
        imagePosition = .imageOnly
        isBordered = false
        title = ""
        toolTip = "Open \(launcher.name)"
        setAccessibilityLabel(toolTip)
        target = self
        action = #selector(launch)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func launch() { NSWorkspace.shared.open(launcher.url) }

    private var runningApplication: NSRunningApplication? {
        guard let identifier = Bundle(url: launcher.url)?.bundleIdentifier else { return nil }
        return NSRunningApplication.runningApplications(withBundleIdentifier: identifier).first(where: { !$0.isTerminated })
    }

    private func children(_ element: AXUIElement) -> [AXUIElement] {
        attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
    }

    private func nativeMenuItem(_ element: AXUIElement, app: NSRunningApplication, depth: Int = 0) -> NSMenuItem? {
        guard depth < 4, let title = attribute(element, kAXTitleAttribute) as? String, !title.isEmpty else { return nil }
        let item = ActionMenuItem(title) {
            app.unhide()
            app.activate(options: [])
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                guard !app.isTerminated, NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier else {
                    NSSound.beep(); return
                }
                if AXUIElementPerformAction(element, kAXPressAction as CFString) != .success { NSSound.beep() }
            }
        }
        item.isEnabled = (attribute(element, kAXEnabledAttribute) as? Bool) ?? true
        if let nativeSubmenu = children(element).first(where: { attribute($0, kAXRoleAttribute) as? String == kAXMenuRole }) {
            let submenu = NSMenu(title: title)
            submenu.autoenablesItems = false
            for child in children(nativeSubmenu) {
                if let childItem = nativeMenuItem(child, app: app, depth: depth + 1) { submenu.addItem(childItem) }
            }
            if !submenu.items.isEmpty { item.submenu = submenu }
        }
        return item
    }

    private func newWindowActions(for app: NSRunningApplication) -> [NSMenuItem] {
        guard AXIsProcessTrusted() else { return [] }
        let root = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(root, 0.15)
        guard let value = attribute(root, kAXMenuBarAttribute), CFGetTypeID(value) == AXUIElementGetTypeID() else { return [] }
        let menuBar = unsafeBitCast(value, to: AXUIElement.self)
        var result: [NSMenuItem] = []
        for heading in children(menuBar) {
            guard let title = attribute(heading, kAXTitleAttribute) as? String, ["File", "Shell"].contains(title),
                  let menu = children(heading).first else { continue }
            for element in children(menu) {
                guard let title = attribute(element, kAXTitleAttribute) as? String,
                      title.hasPrefix("New "), let item = nativeMenuItem(element, app: app) else { continue }
                result.append(item)
            }
        }
        return result
    }

    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let heading = NSMenuItem(title: launcher.name, action: nil, keyEquivalent: "")
        heading.isEnabled = false
        menu.addItem(heading)
        menu.addItem(.separator())
        if let app = runningApplication {
            let newActions = newWindowActions(for: app)
            newActions.forEach { menu.addItem($0) }
            if !newActions.isEmpty { menu.addItem(.separator()) }
            if !windows.isEmpty {
                for window in windows {
                    let item = ActionMenuItem(window.title) { [weak self] in self?.onSelect?(window) }
                    item.state = window.focused ? .on : .off
                    if window.minimized { item.title += " (Minimized)" }
                    menu.addItem(item)
                }
                menu.addItem(.separator())
            }
            menu.addItem(ActionMenuItem("Open") { [weak self] in self?.launch() })
            menu.addItem(ActionMenuItem("Show All Windows") {
                app.unhide()
                app.activate(options: [])
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    guard NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier else { return }
                    for down in [true, false] {
                        let key = CGEvent(keyboardEventSource: nil, virtualKey: 125, keyDown: down)
                        key?.flags = .maskControl
                        key?.post(tap: .cghidEventTap)
                    }
                }
            })
            menu.addItem(ActionMenuItem(app.isHidden ? "Show" : "Hide") {
                if app.isHidden { app.unhide(); app.activate(options: []) } else { app.hide() }
            })
            if Bundle(url: launcher.url)?.bundleIdentifier != "com.apple.finder" {
                menu.addItem(ActionMenuItem("Quit") { app.terminate() })
            }
        } else {
            menu.addItem(ActionMenuItem("Open") { [weak self] in self?.launch() })
        }
        menu.addItem(.separator())
        menu.addItem(ActionMenuItem("Show in Finder") { [launcher] in
            NSWorkspace.shared.activateFileViewerSelecting([launcher.url])
        })
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }
}

final class BarView: NSVisualEffectView {
    let brand = BrandView()
    let launchScroll = HorizontalScrollView()
    let launchDocument = NSView()
    let scroll = HorizontalScrollView()
    let document = NSView()
    let menuButton = NSButton()
    let permissionButton = NSButton(title: "Enable Accessibility", target: nil, action: nil)
    let message = NSTextField(labelWithString: "")
    private var buttons: [String: WindowButton] = [:]
    private var entries: [WindowEntry] = []
    private var launchers: [LauncherEntry] = []
    private var launcherButtons: [String: LauncherButton] = [:]
    private var trusted = false
    var onSelect: ((WindowEntry) -> Void)?
    var onMinimize: ((WindowEntry) -> Void)?
    var onClose: ((WindowEntry) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        material = .hudWindow
        blendingMode = .behindWindow
        state = .active
        appearance = NSAppearance(named: .darkAqua)
        wantsLayer = true
        layer?.cornerRadius = 16
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.17).cgColor
        addSubview(brand)
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
        permissionButton.bezelStyle = .rounded
        permissionButton.contentTintColor = accent
        addSubview(permissionButton)
        message.font = .systemFont(ofSize: 12)
        message.textColor = .secondaryLabelColor
        addSubview(message)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(entries: [WindowEntry], trusted: Bool, launchers: [LauncherEntry] = []) {
        self.entries = entries
        self.launchers = launchers
        self.trusted = trusted
        brand.windowCount = entries.count
        brand.appCount = Set(entries.map(\.pid)).count
        if entries.first?.element == nil { brand.appCount = Set(entries.map(\.appName)).count }
        brand.trusted = trusted
        brand.toolTip = "WindowBar · \(entries.count) windows · \(brand.appCount) apps"
        brand.needsDisplay = true
        let launcherKeys = Set(launchers.map { $0.url.path })
        for key in Array(launcherButtons.keys) where !launcherKeys.contains(key) {
            launcherButtons.removeValue(forKey: key)?.removeFromSuperview()
        }
        for launcher in launchers where launcherButtons[launcher.url.path] == nil {
            let button = LauncherButton(launcher)
            button.onSelect = { [weak self] in self?.onSelect?($0) }
            launcherButtons[launcher.url.path] = button
            launchDocument.addSubview(button)
        }
        for launcher in launchers {
            let identifier = Bundle(url: launcher.url)?.bundleIdentifier
            let pid = identifier.flatMap { NSRunningApplication.runningApplications(withBundleIdentifier: $0).first?.processIdentifier }
            launcherButtons[launcher.url.path]?.windows = entries.filter { $0.pid == pid }
        }
        let keys = Set(entries.map(\.id))
        for key in Array(buttons.keys) where !keys.contains(key) {
            buttons.removeValue(forKey: key)?.removeFromSuperview()
        }
        var windowNumbers: [String: Int] = [:]
        for entry in entries {
            let button: WindowButton
            if let existing = buttons[entry.id] { button = existing; button.update(entry) }
            else {
                button = WindowButton(entry: entry)
                button.onSelect = { [weak self] in self?.onSelect?($0) }
                button.onMinimize = { [weak self] in self?.onMinimize?($0) }
                button.onClose = { [weak self] in self?.onClose?($0) }
                buttons[entry.id] = button
                document.addSubview(button)
            }
            let group = entry.pid == 0 ? entry.appName : String(entry.pid)
            windowNumbers[group, default: 0] += 1
            button.windowNumber = windowNumbers[group]!
        }
        permissionButton.isHidden = trusted
        scroll.isHidden = !trusted || entries.isEmpty
        message.isHidden = trusted && !entries.isEmpty
        message.stringValue = trusted ? "Open an app window to see it here." : "See each window. Switch with one click."
        needsLayout = true
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        let launcherWidth = min(CGFloat(launchers.count) * 38, min(220, bounds.width * 0.25))
        let left: CGFloat = launchers.isEmpty ? 56 : 64 + launcherWidth
        brand.frame = NSRect(x: 13, y: 0, width: 32, height: bounds.height)
        let middle = bounds.height / 2
        launchScroll.frame = NSRect(x: 54, y: middle - 18, width: launcherWidth, height: 36)
        launchDocument.frame = NSRect(x: 0, y: 0, width: CGFloat(launchers.count) * 38, height: 36)
        for (index, launcher) in launchers.enumerated() {
            launcherButtons[launcher.url.path]?.frame = NSRect(x: CGFloat(index) * 38, y: 2, width: 32, height: 32)
        }
        menuButton.frame = NSRect(x: bounds.width - 42, y: middle - 16, width: 28, height: 32)
        scroll.frame = NSRect(x: left, y: 7, width: max(0, bounds.width - left - 50), height: bounds.height - 14)
        let count = CGFloat(max(entries.count, 1))
        let gap: CGFloat = count > 10 ? 4 : 6
        let hasFocusedWindow = entries.contains(where: \.focused)
        let focusScale: CGFloat = hasFocusedWindow ? 1.3 : 1
        let weightedCount = count + (hasFocusedWindow ? focusScale - 1 : 0)
        let width = max(42, min(225, (scroll.bounds.width - max(0, count - 1) * gap) / weightedCount))
        let oldX = scroll.contentView.bounds.minX
        let totalWidth = weightedCount * width + max(0, count - 1) * gap
        document.frame = NSRect(x: 0, y: 0, width: max(scroll.bounds.width, totalWidth), height: scroll.bounds.height)
        NSAnimationContext.runAnimationGroup { context in
            let animate = window != nil && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            context.duration = animate ? 0.22 : 0
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            var x: CGFloat = 0
            for entry in entries {
                let buttonWidth = width * (entry.focused ? focusScale : 1)
                let frame = NSRect(x: x, y: 0, width: buttonWidth, height: 52)
                if let button = buttons[entry.id] {
                    if !animate || button.frame.isEmpty { button.frame = frame }
                    else if button.frame != frame { button.animator().frame = frame }
                    button.needsDisplay = true
                }
                x += buttonWidth + gap
            }
        }
        scroll.contentView.scroll(to: NSPoint(x: min(oldX, max(0, document.frame.width - scroll.bounds.width)), y: 0))
        permissionButton.frame = NSRect(x: bounds.width - 212, y: middle - 15, width: 156, height: 30)
        message.frame = NSRect(x: left + 10, y: middle - 9, width: max(0, bounds.width - left - (trusted ? 66 : 232)), height: 18)
    }

}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panels: [TaskbarPanel] = []
    private var bars: [BarView] = []
    private var statusItem: NSStatusItem!
    private var timer: Timer?
    private var scanning = false
    private var entries: [WindowEntry] = []
    private let scanner = DispatchQueue(label: "windowbar.accessibility", qos: .utility)
    private var allDisplays = UserDefaults.standard.bool(forKey: "allDisplays")
    private var hidden = false
    private let demo = CommandLine.arguments.contains("--demo")
    private let dock = DockController()
    private var replacesDock = UserDefaults.standard.object(forKey: "replacesDock") as? Bool ?? true
    private var launchers: [LauncherEntry] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        launchers = dockLaunchers()
        if !demo && replacesDock && AXIsProcessTrusted() { replacesDock = dock.enable() }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "rectangle.split.3x1", accessibilityDescription: "WindowBar")
        statusItem.menu = makeMenu()
        rebuildPanels()
        NotificationCenter.default.addObserver(self, selector: #selector(rebuildPanels),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(refresh),
            name: NSWorkspace.didActivateApplicationNotification, object: nil)
        timer = Timer.scheduledTimer(timeInterval: 1.5, target: self, selector: #selector(refresh), userInfo: nil, repeats: true)
        refresh()
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        dock.restore()
    }

    @objc private func rebuildPanels() {
        panels.forEach { $0.close() }
        panels = []
        bars = []
        // The first screen is the display with the menu bar, not the focused window's display.
        let screens = allDisplays ? NSScreen.screens : Array(NSScreen.screens.prefix(1))
        for screen in screens {
            let frame = barFrame(for: screen)
            let panel = TaskbarPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.isReleasedWhenClosed = false
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            panel.hidesOnDeactivate = false
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.title = "WindowBar"
            let bar = BarView(frame: NSRect(origin: .zero, size: frame.size))
            bar.onSelect = { [weak self] in self?.select($0) }
            bar.onMinimize = { [weak self] in self?.minimize($0) }
            bar.onClose = { [weak self] in self?.closeWindow($0) }
            bar.menuButton.target = self
            bar.menuButton.action = #selector(showMenu(_:))
            bar.permissionButton.target = self
            bar.permissionButton.action = #selector(enableAccessibility)
            panel.contentView = bar
            panels.append(panel)
            bars.append(bar)
            if !hidden { panel.orderFrontRegardless() }
        }
        render()
    }

    private func barFrame(for screen: NSScreen) -> NSRect {
        let visible = screen.visibleFrame
        let bottom = replacesDock && !demo ? screen.frame.minY : visible.minY
        let width = max(200, visible.width - 24)
        return NSRect(x: visible.minX + 12, y: bottom + 8, width: width, height: 66)
    }

    @objc private func refresh() {
        // Dock size/auto-hide changes need no relaunch.
        let screens = allDisplays ? NSScreen.screens : Array(NSScreen.screens.prefix(1))
        for (panel, screen) in zip(panels, screens) {
            let frame = barFrame(for: screen)
            if panel.frame != frame { panel.setFrame(frame, display: true) }
        }
        if demo { entries = sampleWindows(); render(); return }
        guard AXIsProcessTrusted() else { entries = []; render(); return }
        if replacesDock && !hidden { replacesDock = dock.enable() }
        guard !scanning else { return }
        scanning = true
        scanner.async { [weak self] in
            let windows = readWindows()
            DispatchQueue.main.async {
                guard let self else { return }
                self.scanning = false
                self.entries = windows
                self.render()
            }
        }
    }

    private func render() {
        let trusted = demo || AXIsProcessTrusted()
        let screens = allDisplays ? NSScreen.screens : Array(NSScreen.screens.prefix(1))
        for (panel, screen) in zip(panels, screens) {
            let frame = barFrame(for: screen)
            if panel.frame != frame { panel.setFrame(frame, display: true) }
        }
        bars.forEach { $0.update(entries: entries, trusted: trusted, launchers: launchers) }
    }

    private func select(_ entry: WindowEntry) {
        guard let window = entry.element, let app = NSRunningApplication(processIdentifier: entry.pid) else { return }
        entries = entries.map { existing in
            var updated = existing
            updated.focused = existing.id == entry.id
            return updated
        }
        render()
        AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        app.unhide()
        app.activate(options: [])
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(AXUIElementCreateApplication(entry.pid), kAXFocusedWindowAttribute as CFString, window)
        // Some apps choose their last key window during activation. Raise the requested one again afterward.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            AXUIElementPerformAction(window, kAXRaiseAction as CFString)
            self?.refresh()
        }
    }

    private func minimize(_ entry: WindowEntry) {
        guard let window = entry.element else { return }
        if entry.minimized { select(entry) }
        else { AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanTrue); refresh() }
    }

    private func closeWindow(_ entry: WindowEntry) {
        guard let window = entry.element, let button = attribute(window, kAXCloseButtonAttribute),
              CFGetTypeID(button) == AXUIElementGetTypeID() else { return }
        AXUIElementPerformAction(unsafeBitCast(button, to: AXUIElement.self), kAXPressAction as CFString)
        refresh()
    }

    @objc private func enableAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
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
            ("Open Downloads", #selector(openDownloads), ""),
            ("Open Trash", #selector(openTrash), ""),
            ("Refresh windows", #selector(refresh), ""),
            ("Enable Accessibility…", #selector(enableAccessibility), ""),
            ("Quit WindowBar", #selector(quit), "q")
        ]
        for (title, action, shortcut) in items {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: shortcut)
            item.target = self
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
        hidden.toggle()
        if hidden { dock.restore() }
        else if replacesDock && !demo && AXIsProcessTrusted() { replacesDock = dock.enable() }
        for panel in panels { if hidden { panel.orderOut(nil) } else { panel.orderFrontRegardless() } }
        statusItem.menu = makeMenu()
    }

    @objc private func toggleDock() {
        replacesDock.toggle()
        if replacesDock && !hidden && !demo && AXIsProcessTrusted() { replacesDock = dock.enable() }
        else { dock.restore() }
        UserDefaults.standard.set(replacesDock, forKey: "replacesDock")
        refresh()
        statusItem.menu = makeMenu()
    }

    @objc private func openDownloads() {
        if let url = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first { NSWorkspace.shared.open(url) }
    }

    @objc private func openTrash() {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash")
        NSWorkspace.shared.open(url)
    }

    @objc private func toggleDisplays() {
        allDisplays.toggle()
        UserDefaults.standard.set(allDisplays, forKey: "allDisplays")
        rebuildPanels()
        statusItem.menu = makeMenu()
    }

    @objc private func quit() { NSApp.terminate(nil) }
}

if let index = CommandLine.arguments.firstIndex(of: "--dock-guard"), CommandLine.arguments.count > index + 2,
   let pid = Int32(CommandLine.arguments[index + 1]), pid > 0 {
    DockController.watch(pid: pid, token: CommandLine.arguments[index + 2])
    exit(0)
}

let app = NSApplication.shared

if CommandLine.arguments.contains("--diagnose") {
    let trusted = AXIsProcessTrusted()
    let windows = readWindows()
    let counts = Dictionary(grouping: windows, by: \.appName).mapValues(\.count)
    let report: [String: Any] = ["accessibilityGranted": trusted, "windowCount": windows.count, "windowsPerApp": counts]
    let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
    print(String(data: data, encoding: .utf8)!)
} else if let index = CommandLine.arguments.firstIndex(of: "--render-preview"), CommandLine.arguments.count > index + 1 {
    let view = BarView(frame: NSRect(x: 0, y: 0, width: 1320, height: 66))
    view.update(entries: sampleWindows(), trusted: true, launchers: dockLaunchers())
    view.layoutSubtreeIfNeeded()
    let image = NSImage(size: view.bounds.size)
    image.lockFocus()
    NSColor(calibratedWhite: 0.09, alpha: 1).setFill()
    NSBezierPath(roundedRect: view.bounds, xRadius: 16, yRadius: 16).fill()
    view.displayIgnoringOpacity(view.bounds, in: NSGraphicsContext.current!)
    image.unlockFocus()
    guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("Could not render preview") }
    try png.write(to: URL(fileURLWithPath: CommandLine.arguments[index + 1]))
    print("Preview rendered")
} else {
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
    withExtendedLifetime(delegate) {}
}

import AppKit
import QuartzCore
import WindowBarCore

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
    var onLaunch: ((LauncherEntry) -> Void)?
    var makeLauncherMenu: ((LauncherEntry, [WindowEntry]) -> NSMenu)?

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
            button.onLaunch = { [weak self] in self?.onLaunch?($0) }
            button.makeContextMenu = { [weak self] launcher, windows in
                self?.makeLauncherMenu?(launcher, windows) ?? NSMenu()
            }
            launcherButtons[launcher.url.path] = button
            launchDocument.addSubview(button)
        }
        for launcher in launchers {
            let identifier = Bundle(url: launcher.url)?.bundleIdentifier
            let pid = identifier.flatMap {
                NSRunningApplication.runningApplications(withBundleIdentifier: $0).first?.processIdentifier
            }
            launcherButtons[launcher.url.path]?.windows = entries.filter {
                $0.pid == pid || ($0.element == nil && $0.appName == launcher.name)
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
                buttons[entry.id] = button
                document.addSubview(button)
            }
            let group = entry.pid == 0 ? entry.appName : String(entry.pid)
            windowNumbers[group, default: 0] += 1
            button.windowNumber = windowNumbers[group, default: 1]
        }
        permissionButton.isHidden = trusted
        scroll.isHidden = !trusted || entries.isEmpty
        message.isHidden = trusted && !entries.isEmpty
        message.stringValue =
            trusted ? "Open an app window to see it here." : "See each window. Switch with one click."
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
            launcherButtons[launcher.url.path]?.frame = NSRect(
                x: CGFloat(index) * 38, y: 2, width: 32, height: 32)
        }
        menuButton.frame = NSRect(x: bounds.width - 42, y: middle - 16, width: 28, height: 32)
        scroll.frame = NSRect(
            x: left, y: 7, width: max(0, bounds.width - left - 50), height: bounds.height - 14)
        let geometry = BarLayout(availableWidth: Double(scroll.bounds.width), focused: entries.map(\.focused))
        let oldX = scroll.contentView.bounds.minX
        document.frame = NSRect(x: 0, y: 0, width: geometry.documentWidth, height: scroll.bounds.height)
        NSAnimationContext.runAnimationGroup { context in
            let animate = window != nil && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            context.duration = animate ? 0.22 : 0
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            for (entry, position) in zip(entries, geometry.buttons) {
                let frame = NSRect(x: position.x, y: 0, width: position.width, height: BarLayout.buttonHeight)
                if let button = buttons[entry.id] {
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
        permissionButton.frame = NSRect(x: bounds.width - 212, y: middle - 15, width: 156, height: 30)
        message.frame = NSRect(
            x: left + 10, y: middle - 9, width: max(0, bounds.width - left - (trusted ? 66 : 232)), height: 18
        )
    }

}

import AppKit
import QuartzCore

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
        let area = NSTrackingArea(
            rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area)
        hoverArea = area
    }

    private func hover(_ amount: CGFloat) {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            hoverAmount = amount
            return
        }
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
        NSColor.white.withAlphaComponent(0.075 + hover * 0.125).blended(withFraction: focus, of: accent)!
            .setStroke()
        path.lineWidth = 1 + focus * 0.8
        path.stroke()
        let iconOnly = bounds.width < 76
        let compact = bounds.width < 140
        let iconSize: CGFloat = compact ? 22 : 27
        let iconX: CGFloat = iconOnly ? (bounds.width - iconSize) / 2 : (compact ? 8 : 11)
        let iconY: CGFloat = iconOnly ? 7 : (bounds.height - iconSize) / 2
        entry.icon?.draw(
            in: NSRect(x: iconX, y: iconY, width: iconSize, height: iconSize), from: .zero,
            operation: .sourceOver, fraction: entry.minimized ? 0.5 : 1, respectFlipped: true, hints: nil)
        if iconOnly {
            let style = NSMutableParagraphStyle()
            style.alignment = .center
            NSAttributedString(
                string: String(windowNumber),
                attributes: [
                    .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .medium),
                    .foregroundColor: entry.focused ? accent : NSColor.secondaryLabelColor,
                    .paragraphStyle: style,
                ]
            ).draw(in: NSRect(x: 0, y: 32, width: bounds.width, height: 15))
        } else {
            let textX: CGFloat = compact ? 36 : 48
            let subtitle = bounds.width >= 112
            drawText(
                entry.title,
                in: NSRect(
                    x: textX, y: subtitle ? 9 : 18, width: max(0, bounds.width - textX - 8), height: 18),
                size: compact ? 11 : 12, weight: .medium,
                color: entry.minimized ? .secondaryLabelColor : .labelColor)
            if subtitle {
                drawText(
                    entry.appName + (entry.minimized ? " · Minimized" : ""),
                    in: NSRect(x: textX, y: 29, width: max(0, bounds.width - textX - 8), height: 15),
                    size: 10, weight: .regular, color: entry.focused ? accent : .secondaryLabelColor)
            }
        }
        if focus > 0.001 {
            accent.withAlphaComponent(focus).setFill()
            let indicatorWidth = min(48, bounds.width - 16)
            NSBezierPath(
                roundedRect: NSRect(
                    x: (bounds.width - indicatorWidth) / 2, y: bounds.height - 5,
                    width: indicatorWidth, height: 3), xRadius: 1.5, yRadius: 1.5
            ).fill()
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
        for (title, action) in [
            ("Switch to window", #selector(selectWindow)),
            (entry.minimized ? "Restore window" : "Minimize window", #selector(minimizeWindow)),
            ("Close window", #selector(closeWindow)),
        ] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }
}

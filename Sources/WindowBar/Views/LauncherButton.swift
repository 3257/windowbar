import AppKit

final class LauncherButton: ReorderableButton {
    let launcher: LauncherEntry
    private var hoverArea: NSTrackingArea?
    var onHover: ((LauncherEntry, [WindowEntry], LauncherButton, Bool) -> Void)?
    var onDismissHover: (() -> Void)?
    var windows: [WindowEntry] = [] {
        didSet { toolTip = windows.contains(where: \.focused) ? nil : "Open \(launcher.name)" }
    }
    var makeContextMenu: ((LauncherEntry, [WindowEntry]) -> NSMenu)?
    init(_ launcher: LauncherEntry) {
        self.launcher = launcher
        super.init(frame: .zero)
        configureReordering(id: launcher.url.path, kind: .launcher)
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
    var onLaunch: ((LauncherEntry) -> Void)?
    @objc private func launch() { onLaunch?(launcher) }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(
            rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area)
        hoverArea = area
    }
    override func mouseEntered(with event: NSEvent) {
        guard !windows.contains(where: \.focused) else {
            onDismissHover?()
            return
        }
        onHover?(launcher, windows, self, true)
    }
    override func mouseExited(with event: NSEvent) { onHover?(launcher, windows, self, false) }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if !windows.isEmpty {
            NSColor.secondaryLabelColor.setFill()
            NSBezierPath(ovalIn: NSRect(x: bounds.midX - 1.5, y: 0, width: 3, height: 3)).fill()
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        onDismissHover?()
        guard let menu = makeContextMenu?(launcher, windows) else { return }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }
}

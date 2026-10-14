import AppKit

final class LauncherButton: NSButton {
    let launcher: LauncherEntry
    var windows: [WindowEntry] = []
    var makeContextMenu: ((LauncherEntry, [WindowEntry]) -> NSMenu)?
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
    var onLaunch: ((LauncherEntry) -> Void)?
    @objc private func launch() { onLaunch?(launcher) }

    override func rightMouseDown(with event: NSEvent) {
        guard let menu = makeContextMenu?(launcher, windows) else { return }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }
}

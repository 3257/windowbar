import AppKit
import WindowBarCore

final class HoverPreviewController {
    private let provider: WindowPreviewProviding
    private let showWindows: Bool
    private var generation = ScanGeneration()
    private var pending: DispatchWorkItem?
    private var panel: TaskbarPanel?
    private(set) var shownEntryID: String?
    private var hoveredEntryID: String?

    init(provider: WindowPreviewProviding = WindowPreviews(), showWindows: Bool = true) {
        self.provider = provider
        self.showWindows = showWindows
    }

    func hover(_ entry: WindowEntry, button: WindowButton, entered: Bool, mode: BarPreferences.PreviewMode) {
        hide()
        guard entered else { return }
        hoveredEntryID = entry.id
        let captured = generation.value
        let task = DispatchWorkItem { [weak self, weak button] in
            guard let self, let button, self.generation.accepts(captured) else { return }
            self.show(entry, above: button, image: nil, unavailable: false)
            if mode == .thumbnails {
                self.provider.preview(entry) { [weak self, weak button] result in
                    guard let self, let button, self.generation.accepts(captured) else { return }
                    switch result {
                    case .image(let image): self.show(entry, above: button, image: image, unavailable: false)
                    case .unavailable: self.show(entry, above: button, image: nil, unavailable: true)
                    }
                }
            }
        }
        pending = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: task)
    }

    func hide() {
        generation.invalidate()
        pending?.cancel()
        pending = nil
        panel?.orderOut(nil)
        shownEntryID = nil
        hoveredEntryID = nil
    }

    func retainOnly(_ ids: Set<String>) {
        if let hoveredEntryID, !ids.contains(hoveredEntryID) { hide() }
    }

    private func show(_ entry: WindowEntry, above button: WindowButton, image: NSImage?, unavailable: Bool) {
        let height: CGFloat = image == nil ? (unavailable ? 104 : 80) : 230
        let width: CGFloat = 280
        if panel == nil {
            let window = TaskbarPanel(
                contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered,
                defer: false)
            window.isReleasedWhenClosed = false
            window.isOpaque = false
            window.backgroundColor = .clear
            window.level = .floating
            window.hasShadow = true
            window.hidesOnDeactivate = false
            window.ignoresMouseEvents = true
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel = window
        }
        let content = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        content.material = .popover
        content.state = .active
        content.wantsLayer = true
        content.layer?.cornerRadius = 12
        let title = NSTextField(wrappingLabelWithString: entry.title)
        title.font = .systemFont(ofSize: 12, weight: .semibold)
        title.frame = NSRect(x: 12, y: height - 48, width: width - 24, height: 36)
        content.addSubview(title)
        let subtitle = NSTextField(
            labelWithString: entry.appName + (entry.profile.map { " · \($0.name)" } ?? "")
                + (entry.minimized ? " · Minimized" : ""))
        subtitle.font = .systemFont(ofSize: 10)
        subtitle.textColor = .secondaryLabelColor
        subtitle.frame = NSRect(x: 12, y: height - 67, width: width - 24, height: 16)
        content.addSubview(subtitle)
        if let image {
            let thumbnail = NSImageView(frame: NSRect(x: 10, y: 10, width: width - 20, height: height - 84))
            thumbnail.image = image
            thumbnail.imageScaling = .scaleProportionallyUpOrDown
            content.addSubview(thumbnail)
        } else if unavailable {
            let label = NSTextField(labelWithString: "Thumbnail unavailable · see Preview settings")
            label.font = .systemFont(ofSize: 10)
            label.textColor = .secondaryLabelColor
            label.frame = NSRect(x: 12, y: 12, width: width - 24, height: 16)
            content.addSubview(label)
        }
        panel?.contentView = content
        if let host = button.window {
            let rect = host.convertToScreen(button.convert(button.bounds, to: nil))
            let screen = host.screen?.visibleFrame ?? rect.insetBy(dx: -width, dy: -height)
            let x = max(screen.minX + 8, min(rect.midX - width / 2, screen.maxX - width - 8))
            let y = min(rect.maxY + 12, screen.maxY - height - 8)
            panel?.setFrame(NSRect(x: x, y: y, width: width, height: height), display: false)
        }
        shownEntryID = entry.id
        if showWindows { panel?.orderFrontRegardless() }
    }
}

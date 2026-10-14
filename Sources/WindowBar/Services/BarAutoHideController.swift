import AppKit
import WindowBarCore

final class BarAutoHideController {
    private var state = AutoHideState()
    private var content: NSView?
    private var transition = ScanGeneration()
    private(set) var shownFrame: NSRect = .zero
    private(set) var edgeFrame: NSRect = .zero
    var hidden: Bool { state.hidden }

    func layout(shownFrame: NSRect, screenFrame: NSRect, panel: NSPanel) {
        let edge = NSRect(x: shownFrame.minX, y: screenFrame.minY, width: shownFrame.width, height: 4)
        guard self.shownFrame != shownFrame || edgeFrame != edge else { return }
        if content == nil { content = panel.contentView }
        self.shownFrame = shownFrame
        edgeFrame = edge
        apply(panel, animated: false)
    }

    func update(
        panel: NSPanel, enabled: Bool, delay: Double, pointer: NSPoint,
        interaction: Bool, now: TimeInterval, animated: Bool = true
    ) {
        let previous = state.hidden
        _ = state.update(
            enabled: enabled, pointerInside: panel.frame == shownFrame && shownFrame.contains(pointer),
            atEdge: edgeFrame.contains(pointer), interaction: interaction, now: now, delay: delay)
        if previous != state.hidden { apply(panel, animated: animated) }
    }

    private func apply(_ panel: NSPanel, animated: Bool) {
        transition.invalidate()
        let captured = transition.value
        let animate =
            animated && panel.isVisible && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if state.hidden {
            if animate {
                NSAnimationContext.runAnimationGroup(
                    { context in
                        context.duration = 0.18
                        panel.animator().alphaValue = 0
                    },
                    completionHandler: { [weak self, weak panel] in
                        guard let self, let panel, self.transition.accepts(captured), self.state.hidden else {
                            return
                        }
                        self.installStrip(panel)
                    })
            } else {
                installStrip(panel)
            }
        } else {
            let wasStrip = panel.frame == edgeFrame
            panel.contentView = content
            panel.ignoresMouseEvents = false
            panel.hasShadow = true
            panel.setFrame(shownFrame, display: false)
            if animate {
                if wasStrip { panel.alphaValue = 0 }
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.18
                    panel.animator().alphaValue = 1
                }
            } else {
                panel.alphaValue = 1
            }
        }
    }

    private func installStrip(_ panel: NSPanel) {
        // Stay inside this screen, including vertically stacked display arrangements.
        let strip = NSVisualEffectView(frame: NSRect(origin: .zero, size: edgeFrame.size))
        strip.material = .popover
        strip.state = .active
        strip.wantsLayer = true
        strip.layer?.cornerRadius = 2
        panel.contentView = strip
        panel.ignoresMouseEvents = true
        panel.hasShadow = false
        panel.setFrame(edgeFrame, display: false)
        panel.alphaValue = 1
    }
}

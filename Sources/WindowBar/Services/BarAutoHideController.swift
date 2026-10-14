import AppKit
import WindowBarCore

final class BarAutoHideController {
    private var state = AutoHideState()
    private(set) var shownFrame: NSRect = .zero
    private(set) var edgeFrame: NSRect = .zero
    var hidden: Bool { state.hidden }

    func layout(shownFrame: NSRect, screenFrame: NSRect, panel: NSPanel) {
        self.shownFrame = shownFrame
        edgeFrame = NSRect(x: shownFrame.minX, y: screenFrame.minY, width: shownFrame.width, height: 4)
        apply(panel, animated: false)
    }

    func update(
        panel: NSPanel, enabled: Bool, delay: Double, pointer: NSPoint,
        interaction: Bool, now: TimeInterval, animated: Bool = true
    ) {
        let previous = state.hidden
        _ = state.update(
            enabled: enabled, pointerInside: !state.hidden && shownFrame.contains(pointer),
            atEdge: edgeFrame.contains(pointer), interaction: interaction, now: now, delay: delay)
        if previous != state.hidden { apply(panel, animated: animated) }
    }

    private func apply(_ panel: NSPanel, animated: Bool) {
        var target = shownFrame
        if state.hidden { target.origin.y = edgeFrame.minY - shownFrame.height + edgeFrame.height }
        guard panel.frame != target else { return }
        if animated && panel.isVisible && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                panel.animator().setFrame(target, display: true)
            }
        } else {
            panel.setFrame(target, display: false)
        }
    }
}

import AppKit

final class HorizontalScrollView: NSScrollView {
    override func scrollWheel(with event: NSEvent) {
        guard let documentView else { return }
        let delta =
            abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY)
            ? event.scrollingDeltaX : event.scrollingDeltaY
        let multiplier: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 16
        let maxX = max(0, documentView.frame.width - contentView.bounds.width)
        let x = min(maxX, max(0, contentView.bounds.minX - delta * multiplier))
        contentView.scroll(to: NSPoint(x: x, y: 0))
        reflectScrolledClipView(contentView)
    }
}

import AppKit

final class BrandView: NSView {
    var windowCount = 0
    var appCount = 0
    var trusted = false
    override func draw(_ dirtyRect: NSRect) {
        let y = (bounds.height - 30) / 2
        accent.withAlphaComponent(0.18).setFill()
        NSBezierPath(roundedRect: NSRect(x: 0, y: y, width: 30, height: 30), xRadius: 8, yRadius: 8).fill()
        drawText(
            "W", in: NSRect(x: 6, y: y + 4, width: 22, height: 22), size: 17, weight: .bold, color: accent)
        if bounds.width > 40 {
            drawText(
                "WINDOWBAR", in: NSRect(x: 40, y: 34, width: 115, height: 16), size: 10, weight: .bold,
                color: .labelColor)
            drawText(
                trusted ? "\(windowCount) windows · \(appCount) apps" : "One click to your window",
                in: NSRect(x: 40, y: 17, width: 116, height: 14), size: 9, weight: .regular,
                color: .secondaryLabelColor)
        }
    }
}

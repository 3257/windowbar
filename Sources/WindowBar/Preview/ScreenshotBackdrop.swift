import AppKit

/// A controlled background for actual app screenshots with synthetic window titles.
final class ScreenshotBackdrop: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let top = NSColor(calibratedRed: 0.07, green: 0.10, blue: 0.17, alpha: 1)
        let bottom = NSColor(calibratedRed: 0.04, green: 0.05, blue: 0.08, alpha: 1)
        NSGradient(starting: bottom, ending: top)?.draw(in: bounds, angle: 90)
        drawText(
            "WindowBar", in: NSRect(x: 32, y: bounds.height - 104, width: 700, height: 64),
            size: 44, weight: .semibold, color: .white)
        drawText(
            "Every window, one click away.",
            in: NSRect(x: 34, y: bounds.height - 139, width: 850, height: 32),
            size: 20, weight: .regular, color: NSColor.white.withAlphaComponent(0.6))
        drawText(
            "NATIVE macOS  /  SWIFT",
            in: NSRect(x: bounds.width - 255, y: bounds.height - 68, width: 230, height: 22),
            size: 12, weight: .semibold, color: accent)
        let labels = ["One row", "Individual windows", "Chrome profiles", "Smooth focus"]
        for (index, label) in labels.enumerated() {
            let x = 34 + CGFloat(index) * 180
            NSColor.white.withAlphaComponent(0.055).setFill()
            NSBezierPath(roundedRect: NSRect(x: x, y: 117, width: 166, height: 34), xRadius: 8, yRadius: 8)
                .fill()
            drawText(
                label, in: NSRect(x: x + 12, y: 126, width: 145, height: 18), size: 12, weight: .medium,
                color: NSColor.white.withAlphaComponent(0.75))
        }
    }
}

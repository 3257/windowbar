import CoreGraphics

public enum PeekLayout {
    public static func containsPointer(_ point: CGPoint, source: CGRect, preview: CGRect) -> Bool {
        if source.insetBy(dx: -4, dy: -4).contains(point) || preview.contains(point) { return true }
        guard preview.minY > source.maxY else { return false }
        let x = min(max(source.midX, preview.minX + 8), preview.maxX - 8)
        let bridge = CGMutablePath()
        bridge.move(to: CGPoint(x: source.minX - 4, y: source.maxY - 4))
        bridge.addLine(to: CGPoint(x: source.maxX + 4, y: source.maxY - 4))
        bridge.addLine(to: CGPoint(x: x + 16, y: preview.minY + 4))
        bridge.addLine(to: CGPoint(x: x - 16, y: preview.minY + 4))
        bridge.closeSubpath()
        return bridge.contains(point)
    }
    /// Fit a window preview on the hovered display, leaving the taskbar accessible.
    public static func frame(window: CGRect, screen: CGRect, reservedBottom: CGFloat = 82) -> CGRect? {
        guard window.width.isFinite, window.height.isFinite, window.width > 0, window.height > 0,
            window.minX.isFinite, window.minY.isFinite, screen.width > 32, screen.height > reservedBottom + 32
        else { return nil }
        let available = CGRect(
            x: screen.minX + 16, y: screen.minY + reservedBottom,
            width: screen.width - 32, height: screen.height - reservedBottom - 16)
        let scale = min(1, available.width / window.width, available.height / window.height)
        let size = CGSize(width: window.width * scale, height: window.height * scale)
        return CGRect(
            x: min(max(window.minX, available.minX), available.maxX - size.width),
            y: min(max(window.minY, available.minY), available.maxY - size.height),
            width: size.width, height: size.height)
    }
}

import CoreGraphics

/// A maximized desktop window ends above a visible taskbar, with a small gap.
public struct ReservedWindowArea {
    public let displayID: UInt32
    public let visibleFrame: CGRect
    public let barFrame: CGRect

    public init(displayID: UInt32, visibleFrame: CGRect, barFrame: CGRect) {
        self.displayID = displayID
        self.visibleFrame = visibleFrame
        self.barFrame = barFrame
    }

    public func fittedFrame(for window: CGRect) -> CGRect? {
        guard Self.matches(window, visibleFrame, tolerance: 8), !barFrame.isEmpty,
            visibleFrame.intersects(barFrame)
        else { return nil }
        let bottom = barFrame.maxY + 8
        guard bottom > window.minY, window.maxY - bottom >= 200 else { return nil }
        return CGRect(x: window.minX, y: bottom, width: window.width, height: window.maxY - bottom)
    }

    public static func matches(_ lhs: CGRect, _ rhs: CGRect, tolerance: CGFloat = 2) -> Bool {
        guard !lhs.isEmpty, !rhs.isEmpty, !lhs.isInfinite, !rhs.isInfinite,
            !lhs.isNull, !rhs.isNull
        else { return false }
        return abs(lhs.minX - rhs.minX) <= tolerance && abs(lhs.maxX - rhs.maxX) <= tolerance
            && abs(lhs.minY - rhs.minY) <= tolerance && abs(lhs.maxY - rhs.maxY) <= tolerance
    }

    /// Used only for an explicit restore when WindowBar first saw an already-maximized window.
    public static func defaultRestoredFrame(in frame: CGRect) -> CGRect {
        frame.insetBy(dx: frame.width * 0.12, dy: frame.height * 0.12)
    }
}

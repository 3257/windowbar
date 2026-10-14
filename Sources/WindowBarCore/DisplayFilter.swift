import CoreGraphics
import Foundation

public struct DisplayRegion: Equatable {
    public let id: UInt32
    public let frame: CGRect

    public init(id: UInt32, frame: CGRect) {
        self.id = id
        self.frame = frame
    }
}

public enum DisplayFilter {
    /// Assign a spanning window to the display containing its largest area.
    public static func displayID(for frame: CGRect?, displays: [DisplayRegion]) -> UInt32? {
        guard let frame, !frame.isEmpty, !frame.isInfinite, !frame.isNull else { return nil }
        var best: (id: UInt32, area: CGFloat)?
        for display in displays {
            let overlap = frame.intersection(display.frame)
            let area = overlap.isNull ? 0 : overlap.width * overlap.height
            if area > (best?.area ?? 0) { best = (display.id, area) }
        }
        return best?.id
    }

    public static func cocoaFrame(accessibilityFrame: CGRect, primaryDisplayTop: CGFloat) -> CGRect {
        CGRect(
            x: accessibilityFrame.minX, y: primaryDisplayTop - accessibilityFrame.maxY,
            width: accessibilityFrame.width, height: accessibilityFrame.height)
    }
}

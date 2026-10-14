import CoreGraphics
import Foundation

public struct CaptureWindow {
    public let id: UInt32
    public let pid: Int32
    public let frame: CGRect
    public let title: String?

    public init(id: UInt32, pid: Int32, frame: CGRect, title: String?) {
        self.id = id
        self.pid = pid
        self.frame = frame
        self.title = title
    }
}

public enum WindowCaptureMatcher {
    /// Ambiguous matches intentionally produce no image; never capture the wrong window.
    public static func match(pid: Int32, frame: CGRect?, title: String, candidates: [CaptureWindow])
        -> UInt32?
    {
        guard let frame else { return nil }
        let matching = candidates.filter {
            $0.pid == pid && abs($0.frame.minX - frame.minX) <= 2
                && abs($0.frame.minY - frame.minY) <= 2 && abs($0.frame.width - frame.width) <= 2
                && abs($0.frame.height - frame.height) <= 2
        }
        let named = matching.filter { $0.title == title }
        if named.count == 1 { return named.first?.id }
        return matching.count == 1 ? matching.first?.id : nil
    }
}

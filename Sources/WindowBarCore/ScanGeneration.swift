/// Reject results captured before a selection or permission change.
public struct ScanGeneration {
    public private(set) var value: UInt64 = 0

    public init() {}

    public mutating func invalidate() { value &+= 1 }

    public func accepts(_ captured: UInt64) -> Bool { captured == value }
}

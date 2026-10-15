import Foundation

/// Clock and pointer input are supplied by the host; no global event hooks are needed.
public struct AutoHideState {
    public private(set) var hidden = false
    private var outsideSince: TimeInterval?
    public init() {}

    public mutating func update(
        enabled: Bool, pointerInside: Bool, atEdge: Bool, interaction: Bool,
        now: TimeInterval, delay: TimeInterval
    ) -> Bool {
        if !enabled || interaction || pointerInside || atEdge {
            hidden = false
            outsideSince = nil
        } else {
            let started = outsideSince.flatMap { now >= $0 ? $0 : nil } ?? now
            outsideSince = started
            if now - started >= max(0, delay) { hidden = true }
        }
        return hidden
    }
}

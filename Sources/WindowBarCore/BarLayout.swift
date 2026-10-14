import Foundation

/// Geometry independent of AppKit, Accessibility, and the running desktop.
public struct BarLayout {
    public static let height: Double = 66
    public static let buttonHeight: Double = 52
    public static let focusedScale: Double = 1.3
    public static let minimumButtonWidth: Double = 42
    public static let maximumButtonWidth: Double = 225

    public struct Button: Equatable {
        public let x: Double
        public let width: Double
    }

    public let buttons: [Button]
    public let documentWidth: Double

    public init(availableWidth: Double, focused: [Bool]) {
        let available = max(0, availableWidth)
        guard !focused.isEmpty else {
            buttons = []
            documentWidth = available
            return
        }
        let gap: Double = focused.count > 10 ? 4 : 6
        let weights = focused.map { $0 ? Self.focusedScale : 1 }
        let totalWeight = weights.reduce(0, +)
        let gaps = Double(focused.count - 1) * gap
        let baseWidth = max(
            Self.minimumButtonWidth, min(Self.maximumButtonWidth, (available - gaps) / totalWeight))
        var nextX: Double = 0
        buttons = weights.map { weight in
            let button = Button(x: nextX, width: baseWidth * weight)
            nextX += button.width + gap
            return button
        }
        documentWidth = max(available, nextX - gap)
    }
}

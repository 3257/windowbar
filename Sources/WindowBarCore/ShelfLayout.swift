import Foundation

public struct ShelfLayout {
    public let launcherX: Double
    public let launcherWidth: Double
    public let windowX: Double
    public let windowWidth: Double
    public let dividerX: Double

    public init(width: Double, pinnedCount: Int, searchEnabled: Bool, side: BarPreferences.PinnedSide) {
        let start: Double = searchEnabled ? 46 : 12
        let end = max(start, width - 54)
        launcherWidth = min(
            Double(max(0, pinnedCount)) * 38, min(220, max(0, width) * 0.25), max(0, end - start - 54))
        let gap: Double = pinnedCount > 0 ? 12 : 0
        switch side {
        case .right:
            launcherX = end - launcherWidth
            windowX = start
            dividerX = launcherX - 10
        case .left:
            launcherX = start
            windowX = start + launcherWidth + gap
            dividerX = start + launcherWidth + 6
        }
        windowWidth = max(0, end - start - launcherWidth - gap - 6)
    }
}

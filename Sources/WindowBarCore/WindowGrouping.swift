import Foundation

public struct GroupingWindow {
    public let id: String
    public let appKey: String
    public let appName: String
    public let profileKey: String?
    public let profileName: String?

    public init(
        id: String, appKey: String, appName: String, profileKey: String? = nil, profileName: String? = nil
    ) {
        self.id = id
        self.appKey = appKey
        self.appName = appName
        self.profileKey = profileKey
        self.profileName = profileName
    }
}

public struct WindowGroup: Equatable {
    public let key: String
    public let title: String
    public var windowIDs: [String]
}

public enum WindowGrouping {
    public static func groups(_ windows: [GroupingWindow], mode: BarPreferences.GroupingMode) -> [WindowGroup]
    {
        guard mode != .none else { return [] }
        var groups: [WindowGroup] = []
        var indices: [String: Int] = [:]
        for window in windows {
            // Length-prefix components so app/profile identifiers cannot collide.
            let profile = mode == .appAndProfile ? window.profileKey ?? "" : ""
            let key = "\(window.appKey.utf8.count):\(window.appKey)\(profile.utf8.count):\(profile)"
            if let index = indices[key] {
                groups[index].windowIDs.append(window.id)
            } else {
                indices[key] = groups.count
                let suffix = mode == .appAndProfile ? window.profileName.map { " · \($0)" } ?? "" : ""
                groups.append(WindowGroup(key: key, title: window.appName + suffix, windowIDs: [window.id]))
            }
        }
        return groups
    }
}

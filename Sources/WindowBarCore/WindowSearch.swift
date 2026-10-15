import Foundation

public struct SearchableWindow {
    public let id: String
    public let title: String
    public let app: String
    public let profile: String
    public let minimized: Bool

    public init(id: String, title: String, app: String, profile: String = "", minimized: Bool = false) {
        self.id = id
        self.title = title
        self.app = app
        self.profile = profile
        self.minimized = minimized
    }
}

public enum WindowSearch {
    /// Every whitespace-separated term must match; discovery order remains stable.
    public static func filter(_ windows: [SearchableWindow], query: String, includeMinimized: Bool)
        -> [String]
    {
        let terms = normalized(query).split(whereSeparator: { $0.isWhitespace }).map(String.init)
        return windows.filter { window in
            guard includeMinimized || !window.minimized else { return false }
            let text = normalized([window.title, window.app, window.profile].joined(separator: " "))
            return terms.allSatisfy { text.contains($0) }
        }.map(\.id)
    }

    private static func normalized(_ text: String) -> String {
        text.folding(
            options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }
}

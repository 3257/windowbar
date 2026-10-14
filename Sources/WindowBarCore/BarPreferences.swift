import Foundation

public struct BarPreferences: Equatable, Codable {
    public enum WindowScope: String, CaseIterable, Codable { case allDisplays, currentDisplay }
    public enum PreviewMode: String, CaseIterable, Codable { case titles, thumbnails }

    public var windowScope: WindowScope = .allDisplays
    public var previewMode: PreviewMode = .titles
    public var shortcutsEnabled = false
    public var shortcuts = ShortcutBinding.defaults
    /// nil imports the existing Dock once; [] intentionally shows no pinned apps.
    public var pinnedPaths: [String]?

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case windowScope, previewMode, shortcutsEnabled, shortcuts, pinnedPaths
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        windowScope = try values.decodeIfPresent(WindowScope.self, forKey: .windowScope) ?? .allDisplays
        previewMode = try values.decodeIfPresent(PreviewMode.self, forKey: .previewMode) ?? .titles
        shortcutsEnabled = try values.decodeIfPresent(Bool.self, forKey: .shortcutsEnabled) ?? false
        shortcuts =
            try values.decodeIfPresent([ShortcutBinding].self, forKey: .shortcuts) ?? ShortcutBinding.defaults
        pinnedPaths = try values.decodeIfPresent([String].self, forKey: .pinnedPaths)
    }
}

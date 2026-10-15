import AppKit
import WindowBarCore

final class PreferencesStore {
    private let defaults: UserDefaults
    private let key = "barPreferences.v1"
    private(set) var value: BarPreferences

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key),
            let saved = try? JSONDecoder().decode(BarPreferences.self, from: data)
        {
            value = saved
        } else {
            value = BarPreferences()
        }
    }

    func save(_ updated: BarPreferences) throws {
        try updated.validate()
        let data = try JSONEncoder().encode(updated)
        defaults.set(data, forKey: key)
        defaults.synchronize()
        value = updated
    }

    func persistedValue() -> BarPreferences {
        defaults.synchronize()
        guard let data = defaults.data(forKey: key),
            let saved = try? JSONDecoder().decode(BarPreferences.self, from: data)
        else { return value }
        return saved
    }

    func reload() { value = persistedValue() }

    func importLaunchersIfNeeded(_ launchers: [LauncherEntry]) throws {
        guard value.pinnedPaths == nil else { return }
        var updated = value
        updated.pinnedPaths = launchers.map { $0.url.standardizedFileURL.path }
        try save(updated)
    }

    func launchers() -> [LauncherEntry] {
        var seen = Set<String>()
        return (value.pinnedPaths ?? []).compactMap { path in
            let url = URL(fileURLWithPath: path).standardizedFileURL
            guard url.pathExtension == "app", FileManager.default.fileExists(atPath: url.path),
                seen.insert(url.path).inserted
            else { return nil }
            return LauncherEntry(
                url: url,
                name: Bundle(url: url)?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                    ?? url.deletingPathExtension().lastPathComponent,
                icon: NSWorkspace.shared.icon(forFile: url.path))
        }
    }
}

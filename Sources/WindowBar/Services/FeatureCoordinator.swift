import AppKit
import WindowBarCore

/// Session ordering and persistent pinned-app/preferences state, independent of views.
final class FeatureCoordinator {
    let preferences: PreferencesStore
    private var order = WindowOrdering()
    private var profileOverrides: [String: ChromeProfile] = [:]

    init(preferences: PreferencesStore = PreferencesStore()) { self.preferences = preferences }

    func ordered(_ entries: [WindowEntry]) -> [WindowEntry] {
        order.reconcile(entries.map(\.id))
        let available = Set(entries.map(\.id))
        profileOverrides = profileOverrides.filter { available.contains($0.key) }
        let lookup = Dictionary(entries.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return order.identifiers.compactMap { id in
            guard var entry = lookup[id] else { return nil }
            if let profile = profileOverrides[id] { entry.profile = profile }
            return entry
        }
    }

    func visible(_ entries: [WindowEntry], displayID: UInt32, displays: [DisplayRegion]) -> [WindowEntry] {
        guard preferences.value.windowScope == .currentDisplay else { return entries }
        return entries.filter {
            // Apps without usable bounds remain reachable on each display.
            let assigned = DisplayFilter.displayID(for: $0.frame, displays: displays)
            return assigned == nil || assigned == displayID
        }
    }

    func moveWindow(_ id: String, before target: String) { order.move(id, before: target) }
    func moveWindow(_ id: String, relativeTo target: String, after: Bool) {
        order.move(id, relativeTo: target, after: after)
    }
    func setProfile(_ profile: ChromeProfile?, for id: String) { profileOverrides[id] = profile }
    func profileOverride(for id: String) -> ChromeProfile? { profileOverrides[id] }

    func pin(_ url: URL) throws {
        let path = url.standardizedFileURL.path
        guard url.pathExtension == "app", Bundle(url: url) != nil else { return }
        var updated = preferences.value
        var paths = updated.pinnedPaths ?? []
        if !paths.contains(path) { paths.append(path) }
        updated.pinnedPaths = paths
        try preferences.save(updated)
    }

    func unpin(_ url: URL) throws {
        var updated = preferences.value
        updated.pinnedPaths?.removeAll { $0 == url.standardizedFileURL.path }
        try preferences.save(updated)
    }

    func moveLauncher(_ path: String, before target: String) throws {
        try moveLauncher(path, relativeTo: target, after: false)
    }

    func moveLauncher(_ path: String, relativeTo target: String, after: Bool) throws {
        var updated = preferences.value
        guard var paths = updated.pinnedPaths, path != target, paths.contains(path), paths.contains(target)
        else { return }
        paths.removeAll { $0 == path }
        if let index = paths.firstIndex(of: target) { paths.insert(path, at: index + (after ? 1 : 0)) }
        updated.pinnedPaths = paths
        try preferences.save(updated)
    }
}

import AppKit
import ApplicationServices
import WindowBarCore

final class ChromeWindowProfiles {
    private let store: ChromeProfileProviding
    private let read: (AXUIElement, String) -> Any?
    private var observed: [String: (label: [String], profile: ChromeProfile)] = [:]

    init(
        store: ChromeProfileProviding = ChromeProfileStore(),
        read: @escaping (AXUIElement, String) -> Any? = { attribute($0, $1) }
    ) {
        self.store = store
        self.read = read
    }

    func profiles(for app: NSRunningApplication) -> [ChromeProfile] {
        guard app.bundleIdentifier?.hasPrefix("com.google.Chrome") == true, let url = app.bundleURL else {
            return []
        }
        return store.profiles(for: LauncherEntry(url: url, name: "Chrome", icon: NSImage())) ?? []
    }

    func focusedProfile(in application: AXUIElement, profiles: [ChromeProfile]) -> ChromeProfile? {
        guard !profiles.isEmpty,
            let menuBar = Accessibility.element(
                read(application, kAXMenuBarAttribute).map { $0 as CFTypeRef }),
            let heading = children(menuBar).first(where: {
                read($0, kAXTitleAttribute) as? String == "Profiles"
                    && read($0, kAXEnabledAttribute) as? Bool != false
            })
        else { return nil }
        let selected = children(heading).flatMap(children).filter {
            !(read($0, "AXMenuItemMarkChar") as? String ?? "").isEmpty
        }
        guard selected.count == 1, let title = read(selected[0], kAXTitleAttribute) as? String else {
            return nil
        }
        return ProfileBadgeMatcher.matchMenuItem(title, profiles: profiles)
    }

    func retainOnly(_ ids: Set<String>) { observed = observed.filter { ids.contains($0.key) } }

    func profile(
        for window: AXUIElement, profiles: [ChromeProfile], id: String = "",
        focusedProfile: ChromeProfile? = nil
    ) -> ChromeProfile? {
        guard !profiles.isEmpty else { return nil }
        var remaining = 160
        let deadline = Date().addingTimeInterval(0.15)
        func visit(_ node: AXUIElement, depth: Int) -> [String]? {
            guard depth < 12, remaining > 0, Date() < deadline else { return nil }
            remaining -= 1
            AXUIElementSetMessagingTimeout(node, 0.03)
            let role = read(node, kAXRoleAttribute) as? String
            guard role != "AXWebArea", role != kAXTextAreaRole else { return nil }
            let descendants = children(node)
            if role == kAXToolbarRole {
                // Bookmarks and tab-group toolbars have names. Only the unnamed
                // navigation toolbar's avatar immediately before its menu is trusted.
                guard (read(node, kAXTitleAttribute) as? String ?? "").isEmpty,
                    (read(node, kAXDescriptionAttribute) as? String ?? "").isEmpty,
                    descendants.count >= 2
                else { return nil }
                let menu = descendants[descendants.count - 1]
                let avatar = descendants[descendants.count - 2]
                guard
                    ["AXPopUpButton", "AXMenuButton"].contains(read(menu, kAXRoleAttribute) as? String ?? ""),
                    read(avatar, kAXRoleAttribute) as? String == kAXButtonRole
                else { return nil }
                return [kAXDescriptionAttribute, kAXTitleAttribute, kAXHelpAttribute].compactMap {
                    read(avatar, $0) as? String
                }.filter { !$0.isEmpty }
            }
            for child in descendants {
                if let labels = visit(child, depth: depth + 1) { return labels }
            }
            return nil
        }
        guard let labels = visit(window, depth: 0), !labels.isEmpty else { return nil }
        guard
            !labels.contains(where: {
                $0.localizedCaseInsensitiveContains("incognito")
                    || $0.localizedCaseInsensitiveContains("guest")
            })
        else {
            observed.removeValue(forKey: id)
            return nil
        }
        let matches = labels.compactMap { ProfileBadgeMatcher.match(controlText: $0, profiles: profiles) }
        let unique = Dictionary(matches.map { ($0.directory, $0) }, uniquingKeysWith: { first, _ in first })
        let detected = unique.count == 1 ? unique.values.first : nil
        if let profile = detected ?? focusedProfile {
            if !id.isEmpty { observed[id] = (labels, profile) }
            return profile
        }
        // Managed Chrome may expose only “Work”. Remember its checked Profiles
        // menu entry after this particular window has been focused.
        if let previous = observed[id], previous.label == labels,
            profiles.contains(where: { $0.directory == previous.profile.directory })
        {
            return previous.profile
        }
        observed.removeValue(forKey: id)
        return nil
    }

    private func children(_ node: AXUIElement) -> [AXUIElement] {
        read(node, kAXChildrenAttribute) as? [AXUIElement] ?? []
    }
}

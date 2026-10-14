import AppKit
import ApplicationServices
import WindowBarCore

final class ChromeWindowProfiles {
    private let store: ChromeProfileProviding
    init(store: ChromeProfileProviding = ChromeProfileStore()) { self.store = store }

    func profiles(for app: NSRunningApplication) -> [ChromeProfile] {
        guard app.bundleIdentifier?.hasPrefix("com.google.Chrome") == true, let url = app.bundleURL else {
            return []
        }
        return store.profiles(for: LauncherEntry(url: url, name: "Chrome", icon: NSImage())) ?? []
    }

    func profile(for window: AXUIElement, profiles: [ChromeProfile]) -> ChromeProfile? {
        guard !profiles.isEmpty else { return nil }
        var remaining = 100
        let deadline = Date().addingTimeInterval(0.08)
        func visit(_ node: AXUIElement, depth: Int) -> ChromeProfile? {
            guard depth < 7, remaining > 0, Date() < deadline else { return nil }
            remaining -= 1
            AXUIElementSetMessagingTimeout(node, 0.03)
            let role = attribute(node, kAXRoleAttribute) as? String
            guard role != "AXWebArea", role != kAXTextAreaRole else { return nil }
            if role == kAXButtonRole || role == "AXMenuButton" {
                let description = attribute(node, kAXDescriptionAttribute) as? String ?? ""
                let help = attribute(node, kAXHelpAttribute) as? String ?? ""
                // Chrome's profile control identifies itself as Profile. Page contents
                // are excluded, so a page button named after a profile cannot label it.
                for text in [description, help] where text.hasPrefix("Profile") {
                    if let profile = ProfileBadgeMatcher.match(controlText: text, profiles: profiles) {
                        return profile
                    }
                }
                if description == "Profile", let title = attribute(node, kAXTitleAttribute) as? String {
                    return ProfileBadgeMatcher.match(controlText: title, profiles: profiles)
                }
            }
            for child in attribute(node, kAXChildrenAttribute) as? [AXUIElement] ?? [] {
                if let profile = visit(child, depth: depth + 1) { return profile }
            }
            return nil
        }
        return visit(window, depth: 0)
    }
}

import AppKit
import ApplicationServices
import WindowBarCore

enum ChromeProfileVerification {
    private final class Tree {
        private var values: [(AXUIElement, [String: Any])] = []
        func node(
            _ role: String, title: String = "", children: [AXUIElement] = [], extra: [String: Any] = [:]
        ) -> AXUIElement {
            let element = AXUIElementCreateApplication(pid_t(90000 + values.count))
            var attributes: [String: Any] = [
                kAXRoleAttribute: role, kAXTitleAttribute: title, kAXChildrenAttribute: children,
            ]
            attributes.merge(extra, uniquingKeysWith: { _, new in new })
            values.append((element, attributes))
            return element
        }
        func read(_ element: AXUIElement, _ key: String) -> Any? {
            values.first { CFEqual($0.0, element) }?.1[key]
        }
        func window(label: String, namedToolbar: String = "", web: Bool = false) -> AXUIElement {
            let avatar = node(kAXButtonRole, title: label)
            let menu = node("AXPopUpButton", title: "Chrome")
            var root = node(kAXToolbarRole, title: namedToolbar, children: [avatar, menu])
            if web { root = node("AXWebArea", children: [root]) }
            for _ in 0..<6 { root = node("AXGroup", children: [root]) }
            return root
        }
    }

    static func run() throws {
        let require = FeatureVerification.require
        let tree = Tree()
        let detector = ChromeWindowProfiles(read: tree.read)
        let personal = ChromeProfile(directory: "Default", name: "Personal")
        let work = ChromeProfile(directory: "Profile 1", name: "Work")
        let profiles = [personal, work]
        try require(
            detector.profile(for: tree.window(label: "Personal"), profiles: profiles) == personal,
            "Plain Chrome avatar name at depth seven was missed")
        try require(
            detector.profile(for: tree.window(label: "Ada (Work)"), profiles: profiles) == work,
            "Account and profile avatar name was missed")
        try require(
            detector.profile(for: tree.window(label: "Work", namedToolbar: "Bookmarks"), profiles: profiles)
                == nil,
            "A bookmark was mistaken for a profile")
        try require(
            detector.profile(for: tree.window(label: "Work", web: true), profiles: profiles) == nil,
            "Page content was mistaken for a profile")
        try require(
            detector.profile(
                for: tree.window(label: "Work"),
                profiles: profiles + [ChromeProfile(directory: "Profile 2", name: "Work")]) == nil,
            "Duplicate profile names were guessed")
        let managed = tree.window(label: "Managed")
        try require(
            detector.profile(for: managed, profiles: profiles, id: "one", focusedProfile: work) == work,
            "Checked profile menu did not identify a generic managed avatar")
        try require(
            detector.profile(for: managed, profiles: profiles, id: "one") == work,
            "Observed managed profile was lost when another app took focus")
        try require(
            detector.profile(for: managed, profiles: profiles, id: "two") == nil,
            "A managed profile was copied to another window")
        try require(
            detector.profile(
                for: tree.window(label: "Incognito (1)"), profiles: profiles, id: "private",
                focusedProfile: work) == nil,
            "Private window inherited the normal profile")
        detector.retainOnly([])
        try require(
            detector.profile(for: managed, profiles: profiles, id: "one") == nil,
            "Closed window profile cache was retained")
        let checked = tree.node(
            "AXMenuItem", title: "Work (ada@example.test)", extra: ["AXMenuItemMarkChar": "✓"])
        let menu = tree.node("AXMenu", children: [checked])
        let heading = tree.node("AXMenuBarItem", title: "Profiles", children: [menu])
        let bar = tree.node("AXMenuBar", children: [heading])
        let app = tree.node("AXApplication", extra: [kAXMenuBarAttribute: bar])
        try require(
            detector.focusedProfile(in: app, profiles: profiles) == work,
            "Checked profile menu account suffix was not recognized")
        print(
            "PASS: Chrome plain/account avatar names, depth-seven toolbar, bookmark/page exclusion, ambiguity and per-window managed profile tracking"
        )
    }
}

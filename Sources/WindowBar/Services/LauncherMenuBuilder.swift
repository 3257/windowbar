import AppKit
import ApplicationServices
import WindowBarCore

protocol LauncherMenuProviding {
    func makeMenu(launcher: LauncherEntry, windows: [WindowEntry], onSelect: @escaping (WindowEntry) -> Void)
        -> NSMenu
}

/// Builds app actions separately from icon drawing and event handling.
final class LauncherMenuBuilder: LauncherMenuProviding {
    private let profiles: ChromeProfileProviding
    private let profileLauncher: ChromeProfileLauncher

    init(
        profiles: ChromeProfileProviding = ChromeProfileStore(),
        profileLauncher: ChromeProfileLauncher = ChromeProfileLauncher()
    ) {
        self.profiles = profiles
        self.profileLauncher = profileLauncher
    }
    private func runningApplication(for launcher: LauncherEntry) -> NSRunningApplication? {
        guard let identifier = Bundle(url: launcher.url)?.bundleIdentifier else { return nil }
        return NSRunningApplication.runningApplications(withBundleIdentifier: identifier).first(where: {
            !$0.isTerminated
        })
    }

    private func children(_ element: AXUIElement) -> [AXUIElement] {
        attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
    }

    private func nativeMenuItem(_ element: AXUIElement, app: NSRunningApplication, depth: Int = 0)
        -> NSMenuItem?
    {
        guard depth < 4, let title = attribute(element, kAXTitleAttribute) as? String, !title.isEmpty else {
            return nil
        }
        let item = ActionMenuItem(title) {
            app.unhide()
            app.activate(options: [])
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                guard !app.isTerminated,
                    NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier
                else {
                    NSSound.beep()
                    return
                }
                if AXUIElementPerformAction(element, kAXPressAction as CFString) != .success {
                    NSSound.beep()
                }
            }
        }
        item.isEnabled = (attribute(element, kAXEnabledAttribute) as? Bool) ?? true
        if let nativeSubmenu = children(element).first(where: {
            attribute($0, kAXRoleAttribute) as? String == kAXMenuRole
        }) {
            let submenu = NSMenu(title: title)
            submenu.autoenablesItems = false
            for child in children(nativeSubmenu) {
                if let childItem = nativeMenuItem(child, app: app, depth: depth + 1) {
                    submenu.addItem(childItem)
                }
            }
            if !submenu.items.isEmpty { item.submenu = submenu }
        }
        return item
    }

    private func newWindowActions(for app: NSRunningApplication) -> [NSMenuItem] {
        guard AXIsProcessTrusted() else { return [] }
        let root = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(root, 0.15)
        guard let menuBar = Accessibility.element(attribute(root, kAXMenuBarAttribute)) else { return [] }
        var result: [NSMenuItem] = []
        for heading in children(menuBar) {
            guard let title = attribute(heading, kAXTitleAttribute) as? String,
                ["File", "Shell"].contains(title),
                let menu = children(heading).first
            else { continue }
            for element in children(menu) {
                guard let title = attribute(element, kAXTitleAttribute) as? String,
                    title.hasPrefix("New "), let item = nativeMenuItem(element, app: app)
                else { continue }
                result.append(item)
            }
        }
        return result
    }

    func makeMenu(launcher: LauncherEntry, windows: [WindowEntry], onSelect: @escaping (WindowEntry) -> Void)
        -> NSMenu
    {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let heading = NSMenuItem(title: launcher.name, action: nil, keyEquivalent: "")
        heading.isEnabled = false
        menu.addItem(heading)
        menu.addItem(.separator())
        if let chromeProfiles = profiles.profiles(for: launcher) {
            let item = NSMenuItem(title: "Profiles", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
            let counts = Dictionary(grouping: chromeProfiles, by: \.name).mapValues(\.count)
            for profile in chromeProfiles {
                let title =
                    counts[profile.name, default: 0] > 1
                    ? "\(profile.name) (\(profile.directory))" : profile.name
                let profileItem = ActionMenuItem(title) { [profileLauncher] in
                    profileLauncher.open(profile, in: launcher)
                }
                profileItem.state = profile.lastUsed ? .on : .off
                menu.addItem(profileItem)
            }
            if chromeProfiles.isEmpty {
                let unavailable = NSMenuItem(title: "No profiles available", action: nil, keyEquivalent: "")
                unavailable.isEnabled = false
                menu.addItem(unavailable)
            }
            menu.addItem(.separator())
        }
        if let app = runningApplication(for: launcher) {
            let newActions = newWindowActions(for: app)
            for action in newActions { menu.addItem(action) }
            if !newActions.isEmpty { menu.addItem(.separator()) }
            if !windows.isEmpty {
                for window in windows {
                    let item = ActionMenuItem(window.title) { onSelect(window) }
                    item.state = window.focused ? .on : .off
                    if window.minimized { item.title += " (Minimized)" }
                    menu.addItem(item)
                }
                menu.addItem(.separator())
            }
            menu.addItem(ActionMenuItem("Open") { [launcher] in NSWorkspace.shared.open(launcher.url) })
            menu.addItem(
                ActionMenuItem("Show All Windows") {
                    app.unhide()
                    app.activate(options: [])
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        guard
                            NSWorkspace.shared.frontmostApplication?.processIdentifier
                                == app.processIdentifier
                        else { return }
                        for down in [true, false] {
                            let key = CGEvent(keyboardEventSource: nil, virtualKey: 125, keyDown: down)
                            key?.flags = .maskControl
                            key?.post(tap: .cghidEventTap)
                        }
                    }
                })
            menu.addItem(
                ActionMenuItem(app.isHidden ? "Show" : "Hide") {
                    if app.isHidden {
                        app.unhide()
                        app.activate(options: [])
                    } else {
                        app.hide()
                    }
                })
            if Bundle(url: launcher.url)?.bundleIdentifier != "com.apple.finder" {
                menu.addItem(ActionMenuItem("Quit") { app.terminate() })
            }
        } else {
            menu.addItem(ActionMenuItem("Open") { [launcher] in NSWorkspace.shared.open(launcher.url) })
        }
        menu.addItem(.separator())
        menu.addItem(
            ActionMenuItem("Show in Finder") { [launcher] in
                NSWorkspace.shared.activateFileViewerSelecting([launcher.url])
            })
        return menu
    }
}

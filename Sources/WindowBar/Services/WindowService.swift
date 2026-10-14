import AppKit
import ApplicationServices

protocol WindowDiscovering {
    func readWindows() -> [WindowEntry]
}

/// Call on one serial queue. A transient AX timeout preserves the last successful
/// app snapshot, while terminated apps disappear on the next successful scan.
final class AccessibilityWindowService: WindowDiscovering {
    private var cached: [WindowEntry] = []
    func readWindows() -> [WindowEntry] {
        guard AXIsProcessTrusted() else {
            cached = []
            return []
        }
        let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        var result: [WindowEntry] = []
        for app in NSWorkspace.shared.runningApplications
        where
            app.activationPolicy == .regular && app.processIdentifier != getpid() && !app.isTerminated
        {
            let appElement = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(appElement, 0.15)
            var rawWindows: CFTypeRef?
            let status = AXUIElementCopyAttributeValue(
                appElement, kAXWindowsAttribute as CFString, &rawWindows)
            if status == .cannotComplete {
                result += cached.filter { $0.pid == app.processIdentifier }.map { entry in
                    var retained = entry
                    retained.focused = entry.focused && entry.pid == frontPID
                    return retained
                }
                continue
            }
            guard status == .success, let windows = rawWindows as? [AXUIElement] else { continue }
            let focusedValue = attribute(appElement, kAXFocusedWindowAttribute)
            for (index, window) in windows.enumerated() {
                AXUIElementSetMessagingTimeout(window, 0.15)
                let role = attribute(window, kAXRoleAttribute) as? String
                guard role == kAXWindowRole else { continue }
                let subrole = attribute(window, kAXSubroleAttribute) as? String
                guard subrole != kAXSystemDialogSubrole else { continue }
                let rawTitle = (attribute(window, kAXTitleAttribute) as? String)?.trimmingCharacters(
                    in: .whitespacesAndNewlines)
                let minimized = (attribute(window, kAXMinimizedAttribute) as? Bool) ?? false
                let focused =
                    app.processIdentifier == frontPID && focusedValue.map { CFEqual($0, window) } == true
                result.append(
                    WindowEntry(
                        id: "\(app.processIdentifier):\(CFHash(window))", pid: app.processIdentifier,
                        appName: app.localizedName ?? "App",
                        title: (rawTitle?.isEmpty == false ? rawTitle : nil) ?? "Window \(index + 1)",
                        icon: app.icon, element: window, minimized: minimized, focused: focused
                    ))
            }
        }
        cached = result.sorted {
            let comparison = $0.appName.localizedCaseInsensitiveCompare($1.appName)
            return comparison == .orderedSame ? $0.id < $1.id : comparison == .orderedAscending
        }
        return cached
    }
}

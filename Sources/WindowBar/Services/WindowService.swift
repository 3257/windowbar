import AppKit
import ApplicationServices
import WindowBarCore

protocol WindowDiscovering {
    func readWindows() -> [WindowEntry]
}

/// Call on one serial queue. A transient AX timeout preserves the last successful
/// app snapshot, while terminated apps disappear on the next successful scan.
final class AccessibilityWindowService: WindowDiscovering {
    private var cached: [WindowEntry] = []
    private let profiles = ChromeWindowProfiles()
    func readWindows() -> [WindowEntry] {
        guard AXIsProcessTrusted() else {
            cached = []
            return []
        }
        let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let primaryTop = CGDisplayBounds(CGMainDisplayID()).height
        let captureCandidates =
            (CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] ?? [])
            .compactMap { values -> CaptureWindow? in
                guard let id = values[kCGWindowNumber as String] as? UInt32,
                    let pid = values[kCGWindowOwnerPID as String] as? Int32,
                    let bounds = values[kCGWindowBounds as String] as? [String: Any],
                    let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                    values[kCGWindowLayer as String] as? Int == 0
                else { return nil }
                return CaptureWindow(
                    id: id, pid: pid, frame: frame, title: values[kCGWindowName as String] as? String)
            }
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
            let appProfiles = profiles.profiles(for: app)
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
                var point = CGPoint.zero
                var size = CGSize.zero
                let positionValue = attribute(window, kAXPositionAttribute)
                let sizeValue = attribute(window, kAXSizeAttribute)
                let hasFrame =
                    positionValue.map {
                        CFGetTypeID($0) == AXValueGetTypeID()
                            && AXValueGetValue(unsafeBitCast($0, to: AXValue.self), .cgPoint, &point)
                    } == true
                    && sizeValue.map {
                        CFGetTypeID($0) == AXValueGetTypeID()
                            && AXValueGetValue(unsafeBitCast($0, to: AXValue.self), .cgSize, &size)
                    } == true
                let axFrame = hasFrame ? CGRect(origin: point, size: size) : nil
                let title = (rawTitle?.isEmpty == false ? rawTitle : nil) ?? "Window \(index + 1)"
                result.append(
                    WindowEntry(
                        id: "\(app.processIdentifier):\(CFHash(window))", pid: app.processIdentifier,
                        appName: app.localizedName ?? "App",
                        title: title, icon: app.icon, element: window, minimized: minimized, focused: focused,
                        frame: axFrame.map {
                            DisplayFilter.cocoaFrame(accessibilityFrame: $0, primaryDisplayTop: primaryTop)
                        },
                        windowID: WindowCaptureMatcher.match(
                            pid: app.processIdentifier, frame: axFrame, title: title,
                            candidates: captureCandidates),
                        profile: profiles.profile(for: window, profiles: appProfiles)
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

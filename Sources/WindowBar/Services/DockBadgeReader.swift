import AppKit
import ApplicationServices
import WindowBarCore

protocol AppBadgeReading { func read() -> [String: UnreadBadge]? }

/// Read only application badge metadata exposed by the Dock. Never inspect notification content.
struct DockBadgeReader: AppBadgeReading {
    func read() -> [String: UnreadBadge]? {
        guard AXIsProcessTrusted(),
            let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first
        else { return nil }
        let root = AXUIElementCreateApplication(dock.processIdentifier)
        AXUIElementSetMessagingTimeout(root, 0.06)
        var result: [String: UnreadBadge] = [:]
        var complete = true
        var remaining = 128
        let deadline = Date().addingTimeInterval(0.15)
        func visit(_ element: AXUIElement, depth: Int) {
            guard depth < 5 else { return }
            guard remaining > 0, Date() < deadline else {
                complete = false
                return
            }
            remaining -= 1
            AXUIElementSetMessagingTimeout(element, 0.03)
            if attribute(element, kAXSubroleAttribute) as? String == "AXApplicationDockItem",
                let url = attribute(element, kAXURLAttribute) as? URL,
                let identifier = Bundle(url: url)?.bundleIdentifier,
                let badge = UnreadBadge.parse(attribute(element, "AXStatusLabel") as? String)
            {
                result[identifier] = badge
            }
            for child in (attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? []).prefix(128) {
                visit(child, depth: depth + 1)
            }
        }
        visit(root, depth: 0)
        return complete ? result : nil
    }
}

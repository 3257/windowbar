import AppKit
import ApplicationServices

func frame(_ window: AXUIElement) -> CGRect? {
    guard let p = value(window, kAXPositionAttribute), let s = value(window, kAXSizeAttribute) else {
        return nil
    }
    var point = CGPoint.zero
    var size = CGSize.zero
    guard AXValueGetValue(unsafeBitCast(p, to: AXValue.self), .cgPoint, &point),
        AXValueGetValue(unsafeBitCast(s, to: AXValue.self), .cgSize, &size)
    else { return nil }
    return CGRect(origin: point, size: size)
}

func matches(_ lhs: CGRect?, _ rhs: CGRect) -> Bool {
    guard let lhs else { return false }
    return abs(lhs.minX - rhs.minX) < 3 && abs(lhs.minY - rhs.minY) < 3
        && abs(lhs.width - rhs.width) < 3 && abs(lhs.height - rhs.height) < 3
}

func waitFor(_ check: () -> Bool) -> Bool {
    for _ in 0..<30 {
        if check() { return true }
        pause(0.15)
    }
    return false
}

func doubleClickTitlebar(_ window: AXUIElement) throws {
    guard let bounds = frame(window) else { throw Failure.check("Missing test window frame") }
    let point = CGPoint(x: bounds.minX + bounds.width * 0.7, y: bounds.minY + 15)
    for click in 1...2 {
        for type in [CGEventType.leftMouseDown, .leftMouseUp] {
            let event = CGEvent(
                mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left)!
            event.setIntegerValueField(.mouseEventClickState, value: Int64(click))
            event.post(tap: .cghidEventTap)
            pause(0.05)
        }
    }
}

func verify() throws {
    let _ = NSApplication.shared
    guard AXIsProcessTrusted(),
        let chrome = NSRunningApplication.runningApplications(withBundleIdentifier: "com.google.Chrome")
            .first,
        let bar = NSRunningApplication.runningApplications(withBundleIdentifier: "local.windowbar.app").first
    else { throw Failure.check("Running WindowBar, Chrome and Accessibility access are required") }
    let original = NSWorkspace.shared.frontmostApplication
    let originalWindow = original.flatMap {
        element(value(AXUIElementCreateApplication($0.processIdentifier), kAXFocusedWindowAttribute))
    }
    let chromeAX = AXUIElementCreateApplication(chrome.processIdentifier)
    let before = value(chromeAX, kAXWindowsAttribute) as? [AXUIElement] ?? []
    var scriptError: NSDictionary?
    NSAppleScript(
        source: """
            tell application "Google Chrome"
                set testWindow to make new window with properties {bounds:{140, 100, 1140, 800}}
                set URL of active tab of testWindow to "about:blank"
            end tell
            """)!.executeAndReturnError(&scriptError)
    guard scriptError == nil,
        let testWindow = (value(chromeAX, kAXWindowsAttribute) as? [AXUIElement] ?? []).first(where: {
            window in !before.contains(where: { CFEqual($0, window) })
        })
    else {
        throw Failure.check(
            "Could not create a separate blank Chrome window: \(String(describing: scriptError))")
    }
    defer {
        if let close = element(value(testWindow, kAXCloseButtonAttribute)) {
            AXUIElementPerformAction(close, kAXPressAction as CFString)
        }
        original?.activate(options: [])
        if let originalWindow { AXUIElementPerformAction(originalWindow, kAXRaiseAction as CFString) }
    }
    chrome.activate(options: [])
    pause(2)
    let normal = frame(testWindow)!
    let barAX = AXUIElementCreateApplication(bar.processIdentifier)
    guard
        let panel = (value(barAX, kAXWindowsAttribute) as? [AXUIElement] ?? []).first(where: {
            value($0, kAXTitleAttribute) as? String == "WindowBar"
        }), let barFrame = frame(panel)
    else { throw Failure.check("Taskbar frame unavailable") }
    try doubleClickTitlebar(testWindow)
    try require(
        waitFor {
            guard let current = frame(testWindow) else { return false }
            return current.width > normal.width && abs(current.maxY - (barFrame.minY - 8)) < 3
        },
        "Double-click-maximized Chrome still overlaps the taskbar: \(String(describing: frame(testWindow)))")
    print("PASS: real titlebar double-click maximizes Chrome above taskbar with 8 pt clearance")
    try doubleClickTitlebar(testWindow)
    try require(
        waitFor { matches(frame(testWindow), normal) }, "Second double-click did not restore normal bounds")
    print("PASS: second titlebar double-click restores the previous ordinary window size")
    pause(1.7)
    try require(matches(frame(testWindow), normal), "Ordinary window was changed on a later scan")
    print("PASS: ordinary window remains unchanged across later scans; temporary Chrome window closed")
}

do { try verify() } catch {
    fputs("FAIL: \(error)\n", stderr)
    exit(1)
}

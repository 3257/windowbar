import AppKit
import ApplicationServices

func leftClick(_ button: AXUIElement) throws {
    guard let position = value(button, kAXPositionAttribute), let extent = value(button, kAXSizeAttribute)
    else { throw Failure.check("Window button has no screen position") }
    var point = CGPoint.zero
    var size = CGSize.zero
    AXValueGetValue(unsafeBitCast(position, to: AXValue.self), .cgPoint, &point)
    AXValueGetValue(unsafeBitCast(extent, to: AXValue.self), .cgSize, &size)
    point.x += size.width / 2
    point.y += size.height / 2
    for type in [CGEventType.leftMouseDown, .leftMouseUp] {
        CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left)?
            .post(tap: .cghidEventTap)
    }
    pause(0.4)
}

func terminalWindowIDs() throws -> Set<Int> {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    process.arguments = ["-e", "tell application \"Terminal\" to get id of windows"]
    let output = Pipe()
    process.standardOutput = output
    try process.run()
    process.waitUntilExit()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    try require(process.terminationStatus == 0, "Could not read Terminal window IDs")
    return Set(
        String(decoding: data, as: UTF8.self).split(separator: ",").compactMap {
            Int($0.trimmingCharacters(in: .whitespacesAndNewlines))
        })
}

func closeTestWindows(_ identifiers: Set<Int>) {
    guard !identifiers.isEmpty else { return }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    let list = identifiers.sorted().map(String.init).joined(separator: ",")
    process.arguments = [
        "-e",
        """
        tell application "Terminal"
            repeat with identifier in {\(list)}
                if exists window id identifier then close window id identifier
            end repeat
        end tell
        """,
    ]
    do {
        try process.run()
        process.waitUntilExit()
    } catch { fputs("Could not close owned Terminal test windows\n", stderr) }
}

func focusedTabCount(_ root: AXUIElement) throws -> Int {
    guard let window = element(value(root, kAXFocusedWindowAttribute)) else {
        throw Failure.check("Terminal has no focused window")
    }
    // A single tab has no tab bar. Terminal changes the AX window handle when
    // selecting a new tab, so inspect the current focused handle each time.
    return max(1, tabs(window))
}

func chooseNativeAction(_ title: String, launcher: AXUIElement, bar: AXUIElement) throws {
    rightClick(launcher)
    guard
        let heading = descendants(bar).first(where: {
            value($0, kAXRoleAttribute) as? String == kAXMenuItemRole
                && value($0, kAXTitleAttribute) as? String == title
        })
    else { throw Failure.check("Terminal menu is missing \(title)") }
    // Terminal's New Window/New Tab entries contain its configured profiles.
    let children = descendants(heading).dropFirst().filter {
        value($0, kAXRoleAttribute) as? String == kAXMenuItemRole
            && value($0, kAXEnabledAttribute) as? Bool == true
    }
    let action = children.first ?? heading
    if !children.isEmpty, let position = value(heading, kAXPositionAttribute),
        let extent = value(heading, kAXSizeAttribute)
    {
        var point = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(unsafeBitCast(position, to: AXValue.self), .cgPoint, &point)
        AXValueGetValue(unsafeBitCast(extent, to: AXValue.self), .cgSize, &size)
        point.x += size.width / 2
        point.y += size.height / 2
        CGEvent(
            mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)?
            .post(tap: .cghidEventTap)
        pause(0.6)
    }
    try leftClick(action)
    pause(0.8)
}

func verify() throws {
    let _ = NSApplication.shared
    guard AXIsProcessTrusted(),
        let terminal = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Terminal")
            .first,
        let bar = NSRunningApplication.runningApplications(withBundleIdentifier: "local.windowbar.app").first,
        let chrome = NSRunningApplication.runningApplications(withBundleIdentifier: "com.google.Chrome")
            .first
    else { throw Failure.check("Terminal, Chrome, WindowBar, and Accessibility are required") }
    let previous = NSWorkspace.shared.frontmostApplication
    let previousWindow = previous.flatMap {
        element(value(AXUIElementCreateApplication($0.processIdentifier), kAXFocusedWindowAttribute))
    }
    let root = AXUIElementCreateApplication(terminal.processIdentifier)
    let barRoot = AXUIElementCreateApplication(bar.processIdentifier)
    guard
        let launcher = descendants(barRoot).first(where: {
            value($0, kAXDescriptionAttribute) as? String == "Open Terminal"
        })
    else { throw Failure.check("Terminal launcher not found") }
    let before = value(root, kAXWindowsAttribute) as? [AXUIElement] ?? []
    let originalIDs = try terminalWindowIDs()
    var ownedIDs: Set<Int> = []
    var testWindow: AXUIElement?
    defer {
        closeTestWindows(ownedIDs)
        previous?.activate(options: [])
        if let previousWindow { AXUIElementPerformAction(previousWindow, kAXRaiseAction as CFString) }
    }
    try chooseNativeAction("New Window", launcher: launcher, bar: barRoot)
    ownedIDs.formUnion(try terminalWindowIDs().subtracting(originalIDs))
    let after = value(root, kAXWindowsAttribute) as? [AXUIElement] ?? []
    testWindow = after.first { candidate in !before.contains(where: { CFEqual($0, candidate) }) }
    guard let testWindow else { throw Failure.check("Terminal menu did not open an isolated window") }
    try require(after.count == before.count + 1, "Terminal window count did not increase by one")
    print("PASS: Terminal right-click menu opens a new window")
    pause(2)
    let title = value(testWindow, kAXTitleAttribute) as? String ?? ""
    guard
        let button = descendants(barRoot).last(where: {
            value($0, kAXRoleAttribute) as? String == kAXButtonRole
                && value($0, kAXDescriptionAttribute) as? String == "Terminal — \(title)"
        })
    else { throw Failure.check("Isolated Terminal window button not found") }
    chrome.activate(options: [])
    pause(0.4)
    try leftClick(button)
    let focused = element(value(root, kAXFocusedWindowAttribute))
    try require(
        NSWorkspace.shared.frontmostApplication?.processIdentifier == terminal.processIdentifier
            && focused.map { CFEqual($0, testWindow) } == true,
        "Taskbar click did not focus the isolated Terminal window")
    print("PASS: real taskbar click switches from Chrome to the correct Terminal window")
    let initial = try focusedTabCount(root)
    try shortcut(17)
    ownedIDs.formUnion(try terminalWindowIDs().subtracting(originalIDs))
    try require(try focusedTabCount(root) == initial + 1, "Command-T did not open a Terminal tab")
    print("PASS: Terminal Command-T opens a tab after taskbar selection")
    try chooseNativeAction("New Tab", launcher: launcher, bar: barRoot)
    ownedIDs.formUnion(try terminalWindowIDs().subtracting(originalIDs))
    try require(try focusedTabCount(root) == initial + 2, "Terminal right-click New Tab did not open a tab")
    print("PASS: Terminal right-click menu opens a new tab")
}

do { try verify() } catch {
    fputs("FAIL: \(error)\n", stderr)
    exit(1)
}

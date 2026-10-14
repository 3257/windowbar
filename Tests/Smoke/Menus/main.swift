import AppKit
import ApplicationServices

func verify() throws {
    let _ = NSApplication.shared
    guard AXIsProcessTrusted(),
        let chrome = NSRunningApplication.runningApplications(withBundleIdentifier: "com.google.Chrome")
            .first,
        let bar = NSRunningApplication.runningApplications(withBundleIdentifier: "local.windowbar.app").first
    else {
        throw Failure.check("Chrome, WindowBar and Accessibility permission are required")
    }
    let previous = NSWorkspace.shared.frontmostApplication
    let previousWindow = previous.flatMap {
        element(value(AXUIElementCreateApplication($0.processIdentifier), kAXFocusedWindowAttribute))
    }
    var profileWindow: AXUIElement?
    var testWindow: AXUIElement?
    defer {
        if let profileWindow, let close = element(value(profileWindow, kAXCloseButtonAttribute)) {
            AXUIElementPerformAction(close, kAXPressAction as CFString)
        }
        if let testWindow, let close = element(value(testWindow, kAXCloseButtonAttribute)) {
            AXUIElementPerformAction(close, kAXPressAction as CFString)
        }
        previous?.activate(options: [])
        if let previousWindow { AXUIElementPerformAction(previousWindow, kAXRaiseAction as CFString) }
    }
    let barAX = AXUIElementCreateApplication(bar.processIdentifier)
    let chromeAX = AXUIElementCreateApplication(chrome.processIdentifier)
    guard
        let launcher = descendants(barAX).first(where: {
            value($0, kAXDescriptionAttribute) as? String == "Open Google Chrome"
        })
    else {
        throw Failure.check("Chrome launcher not found")
    }
    let before = value(chromeAX, kAXWindowsAttribute) as? [AXUIElement] ?? []
    rightClick(launcher)
    let items = descendants(barAX).filter { value($0, kAXRoleAttribute) as? String == kAXMenuItemRole }
    let expected: Set<String> = [
        "New Tab", "New Window", "New Incognito Window", "Open", "Show All Windows", "Hide", "Quit",
        "Show in Finder", "Profiles",
    ]
    let names = Set(items.compactMap { value($0, kAXTitleAttribute) as? String })
    try require(
        expected.isSubset(of: names), "Pinned Chrome menu is missing: \(expected.subtracting(names).sorted())"
    )
    guard let newWindow = items.first(where: { value($0, kAXTitleAttribute) as? String == "New Window" })
    else {
        throw Failure.check("New Window menu item not found")
    }
    try require(
        AXUIElementPerformAction(newWindow, kAXPressAction as CFString) == .success,
        "Could not choose New Window")
    pause(0.8)
    let after = value(chromeAX, kAXWindowsAttribute) as? [AXUIElement] ?? []
    testWindow = after.first(where: { candidate in !before.contains(where: { CFEqual($0, candidate) }) })
    try require(
        after.count == before.count + 1 && testWindow != nil,
        "Native New Window action did not create a window")
    guard let testWindow else { throw Failure.check("Isolated window missing") }
    rightClick(launcher)
    guard
        let newTab = descendants(barAX).first(where: {
            value($0, kAXRoleAttribute) as? String == kAXMenuItemRole
                && value($0, kAXTitleAttribute) as? String == "New Tab"
        })
    else {
        throw Failure.check("New Tab menu item not found")
    }
    try require(
        AXUIElementPerformAction(newTab, kAXPressAction as CFString) == .success, "Could not choose New Tab")
    pause(0.6)
    let tabCount = descendants(testWindow).filter {
        value($0, kAXRoleAttribute) as? String == kAXRadioButtonRole
    }.count
    try require(tabCount == 2, "Native New Tab action did not create a tab in the isolated window")
    pause(1.7)
    let buttonSizes = descendants(barAX).filter {
        value($0, kAXRoleAttribute) as? String == kAXButtonRole
            && (value($0, kAXDescriptionAttribute) as? String ?? "").contains(" — ")
    }.compactMap { button -> CGFloat? in
        guard let raw = value(button, kAXSizeAttribute) else { return nil }
        var size = CGSize.zero
        AXValueGetValue(unsafeBitCast(raw, to: AXValue.self), .cgSize, &size)
        return size.width
    }
    if let smallest = buttonSizes.min(), let largest = buttonSizes.max() {
        try require(largest / smallest > 1.25 && largest / smallest < 1.35, "Focused window is not 30% wider")
    }
    print("PASS: Chrome pinned menu exposes Dock actions")
    print("PASS: native New Window and New Tab actions")
    print("PASS: focused window is 30% wider")
    rightClick(launcher)
    let profileItems = descendants(barAX).filter { value($0, kAXRoleAttribute) as? String == kAXMenuItemRole }
    let stateURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
        "Library/Application Support/Google/Chrome/Local State")
    let state = try JSONSerialization.jsonObject(with: Data(contentsOf: stateURL)) as? [String: Any]
    let metadata = state?["profile"] as? [String: Any]
    let cache = metadata?["info_cache"] as? [String: [String: Any]] ?? [:]
    let profileNames = cache.map { directory, metadata -> String in
        let name = metadata["name"] as? String ?? directory
        let duplicates = cache.values.filter { $0["name"] as? String == name }.count
        return duplicates > 1 ? "\(name) (\(directory))" : name
    }
    let visibleNames = Set(profileItems.compactMap { value($0, kAXTitleAttribute) as? String })
    try require(
        Set(profileNames).isSubset(of: visibleNames), "Chrome root menu does not list every local profile")
    let lastUsed = metadata?["last_used"] as? String ?? "Default"
    let name = cache[lastUsed]?["name"] as? String ?? lastUsed
    let duplicates = cache.values.filter { $0["name"] as? String == name }.count
    let label = duplicates > 1 ? "\(name) (\(lastUsed))" : name
    guard let selected = profileItems.first(where: { value($0, kAXTitleAttribute) as? String == label })
    else {
        throw Failure.check("Last-used Chrome profile is missing")
    }
    let beforeProfile = value(chromeAX, kAXWindowsAttribute) as? [AXUIElement] ?? []
    try require(
        AXUIElementPerformAction(selected, kAXPressAction as CFString) == .success, "Cannot choose profile")
    for _ in 0..<24 {
        pause(0.25)
        let current = value(chromeAX, kAXWindowsAttribute) as? [AXUIElement] ?? []
        profileWindow = current.first(where: { candidate in
            !beforeProfile.contains(where: { CFEqual($0, candidate) })
        })
        if profileWindow != nil { break }
    }
    try require(profileWindow != nil, "Selected Chrome profile did not open a new window")
    print("PASS: all \(cache.count) Chrome profiles are listed and profile selection opens a window")
    if let terminalLauncher = descendants(barAX).first(where: {
        value($0, kAXDescriptionAttribute) as? String == "Open Terminal"
    }) {
        rightClick(terminalLauncher)
        let titles = Set(
            descendants(barAX).filter { value($0, kAXRoleAttribute) as? String == kAXMenuItemRole }
                .compactMap { value($0, kAXTitleAttribute) as? String })
        for down in [true, false] {
            CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: down)?.post(tap: .cghidEventTap)
        }
        pause(0.1)
        try require(
            Set(["New Window", "New Tab", "Quit", "Show in Finder"]).isSubset(of: titles),
            "Terminal menu is missing native Shell actions")
        print("PASS: Terminal pinned menu exposes native Shell actions")
    }
}

do { try verify() } catch {
    fputs("FAIL: \(error)\n", stderr)
    exit(1)
}

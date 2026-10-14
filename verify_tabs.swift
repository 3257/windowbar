import AppKit
import ApplicationServices

func value(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
    var result: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, key as CFString, &result) == .success else { return nil }
    return result
}
func element(_ value: CFTypeRef?) -> AXUIElement? {
    guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
    return unsafeBitCast(value, to: AXUIElement.self)
}
func pause(_ seconds: TimeInterval) { RunLoop.current.run(until: Date().addingTimeInterval(seconds)) }
func shortcut(_ code: CGKeyCode) {
    for down in [true, false] {
        let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down)!
        event.flags = .maskCommand
        event.post(tap: .cghidEventTap)
    }
    pause(0.5)
}
func descendants(_ root: AXUIElement, depth: Int = 0) -> [AXUIElement] {
    guard depth < 12 else { return [root] }
    let children = value(root, kAXChildrenAttribute) as? [AXUIElement] ?? []
    return [root] + children.flatMap { descendants($0, depth: depth + 1) }
}
func tabs(_ window: AXUIElement) -> Int {
    descendants(window).filter { value($0, kAXRoleAttribute) as? String == kAXRadioButtonRole }.count
}

let application = NSApplication.shared
guard AXIsProcessTrusted(),
      let chrome = NSRunningApplication.runningApplications(withBundleIdentifier: "com.google.Chrome").first,
      let bar = NSRunningApplication.runningApplications(withBundleIdentifier: "local.windowbar.app").first else {
    fatalError("Chrome, WindowBar, and Accessibility permission are required")
}
let original = NSWorkspace.shared.frontmostApplication
let originalWindow = original.flatMap { element(value(AXUIElementCreateApplication($0.processIdentifier), kAXFocusedWindowAttribute)) }
let chromeAX = AXUIElementCreateApplication(chrome.processIdentifier)
let beforeWindows = value(chromeAX, kAXWindowsAttribute) as? [AXUIElement] ?? []
chrome.activate(options: [])
pause(0.4)
guard NSWorkspace.shared.frontmostApplication?.processIdentifier == chrome.processIdentifier else {
    fatalError("Chrome did not become active; no test window or keyboard events were created")
}
shortcut(45) // Command-N: make a temporary window; never type into an existing window.
guard let testWindow = element(value(chromeAX, kAXFocusedWindowAttribute)),
      !beforeWindows.contains(where: { CFEqual($0, testWindow) }) else { fatalError("Could not create isolated test window") }
defer {
    if let close = element(value(testWindow, kAXCloseButtonAttribute)) { AXUIElementPerformAction(close, kAXPressAction as CFString) }
    original?.activate(options: [])
    if let originalWindow { AXUIElementPerformAction(originalWindow, kAXRaiseAction as CFString) }
}
let title = value(testWindow, kAXTitleAttribute) as? String ?? ""
pause(2)
let barAX = AXUIElementCreateApplication(bar.processIdentifier)
let controls = descendants(barAX)
let buttons = controls.filter { value($0, kAXRoleAttribute) as? String == kAXButtonRole }
let targetLabel = "Google Chrome — \(title)"
guard let button = buttons.last(where: { value($0, kAXDescriptionAttribute) as? String == targetLabel }),
      let position = value(button, kAXPositionAttribute), let size = value(button, kAXSizeAttribute) else {
    fatalError("Temporary Chrome window button not found")
}
var point = CGPoint.zero
var extent = CGSize.zero
AXValueGetValue(unsafeBitCast(position, to: AXValue.self), .cgPoint, &point)
AXValueGetValue(unsafeBitCast(size, to: AXValue.self), .cgSize, &extent)
point.x += extent.width / 2
point.y += extent.height / 2
if let terminal = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Terminal").first {
    terminal.activate(options: [])
    pause(0.4)
}
for type in [CGEventType.leftMouseDown, .leftMouseUp] {
    CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
}
pause(0.4)
let focused = element(value(chromeAX, kAXFocusedWindowAttribute))
let correctWindow = focused.map { CFEqual($0, testWindow) } ?? false
let frontIsChrome = NSWorkspace.shared.frontmostApplication?.processIdentifier == chrome.processIdentifier
let before = tabs(testWindow)
if frontIsChrome && correctWindow { shortcut(17) } // Command-T
let after = tabs(testWindow)
let addTabButton = descendants(testWindow).first {
    value($0, kAXRoleAttribute) as? String == kAXButtonRole &&
    ((value($0, kAXDescriptionAttribute) as? String ?? "") == "New Tab" ||
     (value($0, kAXTitleAttribute) as? String ?? "") == "New Tab")
}
var plusWorked = false
if let addTabButton, let p = value(addTabButton, kAXPositionAttribute), let s = value(addTabButton, kAXSizeAttribute) {
    var point = CGPoint.zero
    var size = CGSize.zero
    AXValueGetValue(unsafeBitCast(p, to: AXValue.self), .cgPoint, &point)
    AXValueGetValue(unsafeBitCast(s, to: AXValue.self), .cgSize, &size)
    point.x += size.width / 2
    point.y += size.height / 2
    for type in [CGEventType.leftMouseDown, .leftMouseUp] {
        CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
    }
    pause(0.5)
    plusWorked = tabs(testWindow) == after + 1
}
let report: [String: Any] = ["chromeFrontmost": frontIsChrome, "selectedCorrectWindow": correctWindow,
                           "tabsBefore": before, "tabsAfter": after, "newTabOpened": after == before + 1,
                           "plusButtonFound": addTabButton != nil, "plusButtonOpenedTab": plusWorked]
let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
print(String(data: data, encoding: .utf8)!)

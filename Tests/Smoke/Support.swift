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
func descendants(_ root: AXUIElement, depth: Int = 0) -> [AXUIElement] {
    guard depth < 12 else { return [root] }
    return [root]
        + (value(root, kAXChildrenAttribute) as? [AXUIElement] ?? []).flatMap {
            descendants($0, depth: depth + 1)
        }
}
func rightClick(_ button: AXUIElement) {
    var point = CGPoint.zero
    var size = CGSize.zero
    if let p = value(button, kAXPositionAttribute), let s = value(button, kAXSizeAttribute) {
        AXValueGetValue(unsafeBitCast(p, to: AXValue.self), .cgPoint, &point)
        AXValueGetValue(unsafeBitCast(s, to: AXValue.self), .cgSize, &size)
    }
    point.x += size.width / 2
    point.y += size.height / 2
    for type in [CGEventType.rightMouseDown, .rightMouseUp] {
        CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .right)?
            .post(tap: .cghidEventTap)
    }
    pause(0.25)
}
enum Failure: Error { case check(String) }
func require(_ condition: Bool, _ message: String) throws { if !condition { throw Failure.check(message) } }

func shortcut(_ code: CGKeyCode) throws {
    for down in [true, false] {
        guard let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down) else {
            throw Failure.check("Could not create keyboard event")
        }
        event.flags = .maskCommand
        event.post(tap: .cghidEventTap)
    }
    pause(0.5)
}

func tabs(_ window: AXUIElement) -> Int {
    descendants(window).filter { value($0, kAXRoleAttribute) as? String == kAXRadioButtonRole }.count
}

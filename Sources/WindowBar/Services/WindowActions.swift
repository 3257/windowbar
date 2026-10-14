import AppKit
import ApplicationServices

protocol WindowActing {
    func select(_ entry: WindowEntry, completion: @escaping () -> Void)
    func minimize(_ entry: WindowEntry)
    func close(_ entry: WindowEntry)
}

/// Owns window manipulation; views only publish user intent.
final class WindowActions: WindowActing {
    private var selectionGeneration: UInt64 = 0

    func select(_ entry: WindowEntry, completion: @escaping () -> Void) {
        guard let window = entry.element, let app = NSRunningApplication(processIdentifier: entry.pid) else {
            return
        }
        selectionGeneration &+= 1
        let captured = selectionGeneration
        AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        app.unhide()
        app.activate(options: [])
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(
            AXUIElementCreateApplication(entry.pid), kAXFocusedWindowAttribute as CFString, window)
        // Some apps choose their previous key window while activation is pending.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            guard let self, captured == self.selectionGeneration, !app.isTerminated,
                NSWorkspace.shared.frontmostApplication?.processIdentifier == entry.pid
            else { return }
            AXUIElementPerformAction(window, kAXRaiseAction as CFString)
            completion()
        }
    }

    func minimize(_ entry: WindowEntry) {
        guard let window = entry.element else { return }
        AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanTrue)
    }

    func close(_ entry: WindowEntry) {
        guard let window = entry.element,
            let button = Accessibility.element(attribute(window, kAXCloseButtonAttribute))
        else { return }
        AXUIElementPerformAction(button, kAXPressAction as CFString)
    }
}

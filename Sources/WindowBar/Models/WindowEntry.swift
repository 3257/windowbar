import AppKit
import ApplicationServices
import WindowBarCore

struct WindowEntry {
    let id: String
    let pid: pid_t
    let appName: String
    let title: String
    let icon: NSImage?
    let element: AXUIElement?
    let minimized: Bool
    var focused: Bool
    var frame: CGRect? = nil
    var windowID: CGWindowID? = nil
    var profile: ChromeProfile? = nil
}

import AppKit

enum TerminalMenuDefaults {
    /// Keep explicit profile choices alongside the dedicated home-folder action.
    static func actions(from item: NSMenuItem) -> [NSMenuItem] {
        guard item.title == "New Window" else { return [item] }
        guard let submenu = item.submenu, !submenu.items.isEmpty else { return [] }
        item.title = "New Window with Profile"
        return [item]
    }
}

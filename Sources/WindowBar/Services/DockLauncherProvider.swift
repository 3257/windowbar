import AppKit

func dockLaunchers() -> [LauncherEntry] {
    var launchers: [LauncherEntry] = []
    var seen = Set<String>()
    let finder = URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")
    func append(_ url: URL, name: String) {
        guard FileManager.default.fileExists(atPath: url.path),
            seen.insert(url.standardizedFileURL.path).inserted
        else { return }
        launchers.append(
            LauncherEntry(url: url, name: name, icon: NSWorkspace.shared.icon(forFile: url.path)))
    }
    append(finder, name: "Finder")
    let tiles =
        CFPreferencesCopyAppValue("persistent-apps" as CFString, "com.apple.dock" as CFString)
        as? [[String: Any]] ?? []
    for tile in tiles {
        guard let data = tile["tile-data"] as? [String: Any], let file = data["file-data"] as? [String: Any],
            let string = file["_CFURLString"] as? String, let url = URL(string: string), url.isFileURL
        else { continue }
        append(url, name: data["file-label"] as? String ?? url.deletingPathExtension().lastPathComponent)
    }
    return launchers
}

// WindowBar uses public Accessibility APIs. No screen capture or private Dock APIs.

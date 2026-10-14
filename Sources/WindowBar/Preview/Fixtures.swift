import AppKit
import WindowBarCore

func sampleWindows() -> [WindowEntry] {
    let specs: [(String, String, Bool, Bool)] = [
        ("Google Chrome", "Project dashboard", false, true),
        ("Google Chrome", "Research & references", false, false),
        ("Google Chrome", "Personal", true, false),
        ("Terminal", "windowbar — zsh", false, false),
        ("Terminal", "Local dev server", false, false),
    ]
    return specs.enumerated().map { index, spec in
        let path =
            spec.0 == "Terminal"
            ? "/System/Applications/Utilities/Terminal.app" : "/Applications/Google Chrome.app"
        let profiles = [
            ChromeProfile(directory: "Profile 1", name: "Work"),
            ChromeProfile(directory: "Default", name: "Personal"),
            ChromeProfile(directory: "Profile 2", name: "Development"),
        ]
        return WindowEntry(
            id: "demo-\(index)", pid: 0, appName: spec.0, title: spec.1,
            icon: NSWorkspace.shared.icon(forFile: path), element: nil, minimized: spec.2, focused: spec.3,
            profile: index < 3 ? profiles[index] : nil)
    }
}

func sampleLaunchers() -> [LauncherEntry] {
    [
        ("/System/Library/CoreServices/Finder.app", "Finder"),
        ("/Applications/Google Chrome.app", "Google Chrome"),
        ("/System/Applications/Utilities/Terminal.app", "Terminal"),
        ("/System/Applications/Notes.app", "Notes"),
        ("/System/Applications/System Settings.app", "System Settings"),
    ].map { path, name in
        LauncherEntry(
            url: URL(fileURLWithPath: path), name: name, icon: NSWorkspace.shared.icon(forFile: path))
    }
}

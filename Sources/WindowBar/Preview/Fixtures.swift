import AppKit

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
        return WindowEntry(
            id: "demo-\(index)", pid: 0, appName: spec.0, title: spec.1,
            icon: NSWorkspace.shared.icon(forFile: path), element: nil, minimized: spec.2, focused: spec.3)
    }
}

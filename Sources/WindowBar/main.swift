import AppKit
import ApplicationServices
import WindowBarCore

let usage = """
    WindowBar
      --demo                     Show sample windows without changing Dock preferences
      --screenshot-demo          Show sample windows and a screenshot backdrop
      --diagnose                 Report Accessibility status and window counts
      --render-preview PATH      Render a sample bar to PNG
      --render-screenshots PATH   Render native AppKit documentation images
      --help                     Show this help
      --self-test                Run isolated feature checks without changing the desktop
      --install                  Install in ~/Applications without launching or replacing a running copy
    """

do {
    let command = try AppCommand.parse(Array(CommandLine.arguments.dropFirst()))
    switch command {
    case .help:
        print(usage)
    case .selfTest:
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        try FeatureVerification.run()
    case .install:
        NSApplication.shared.setActivationPolicy(.prohibited)
        let installer = ApplicationInstaller()
        try installer.install(from: Bundle.main.bundleURL)
        print("Installed: \(installer.destination.path). Open that copy when convenient.")
    case .guardDock(let pid, let token):
        DockController.watch(pid: pid, token: token)
    case .diagnose:
        NSApplication.shared.setActivationPolicy(.prohibited)
        let windows = AccessibilityWindowService().readWindows()
        let counts = Dictionary(grouping: windows, by: \.appName).mapValues(\.count)
        let report: [String: Any] = [
            "accessibilityGranted": AXIsProcessTrusted(), "windowCount": windows.count,
            "windowsPerApp": counts,
            "thumbnailAccessGranted": CGPreflightScreenCaptureAccess(),
            "startupStatus": String(describing: LoginItemService().status),
        ]
        let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        if let text = String(data: data, encoding: .utf8) { print(text) }
    case .preview(let path):
        NSApplication.shared.setActivationPolicy(.prohibited)
        try PreviewRenderer.write(to: URL(fileURLWithPath: path))
        print("Preview rendered")
    case .screenshots(let path):
        NSApplication.shared.setActivationPolicy(.prohibited)
        try PreviewRenderer.documentation(in: URL(fileURLWithPath: path))
        print("Documentation images rendered")
    case .run(let demo, let screenshots):
        let instance = try InstanceLock(directory: DockController.backupURL.deletingLastPathComponent())
        if !demo {
            Diagnostics.shared.startSession()
            NSSetUncaughtExceptionHandler { _ in Diagnostics.shared.record(.exception) }
        }
        let app = NSApplication.shared
        let menus = LauncherMenuBuilder(profiles: demo ? SampleChromeProfiles() : ChromeProfileStore())
        let delegate = AppDelegate(demo: demo, screenshots: screenshots, launcherMenus: menus)
        app.delegate = delegate
        app.run()
        withExtendedLifetime((delegate, instance)) {}
    }
} catch {
    fputs("WindowBar: \(error)\n\(usage)\n", stderr)
    exit(1)
}

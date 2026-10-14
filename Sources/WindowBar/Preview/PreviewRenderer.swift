import AppKit
import WindowBarCore

enum PreviewRenderer {
    enum RenderingError: Error { case bitmapUnavailable }

    static func write(to url: URL) throws {
        let view = BarView(frame: NSRect(x: 0, y: 0, width: 1320, height: BarLayout.height))
        view.update(entries: sampleWindows(), trusted: true, launchers: dockLaunchers())
        view.layoutSubtreeIfNeeded()
        let image = NSImage(size: view.bounds.size)
        image.lockFocus()
        NSColor(calibratedWhite: 0.09, alpha: 1).setFill()
        NSBezierPath(roundedRect: view.bounds, xRadius: 16, yRadius: 16).fill()
        guard let context = NSGraphicsContext.current else {
            image.unlockFocus()
            throw RenderingError.bitmapUnavailable
        }
        view.displayIgnoringOpacity(view.bounds, in: context)
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
            let png = bitmap.representation(using: .png, properties: [:])
        else { throw RenderingError.bitmapUnavailable }
        try png.write(to: url)
    }

    /// Captures only views owned by this process. No desktop or screen recording.
    static func documentation(in directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let previousAppearance = app.appearance
        app.appearance = NSAppearance(named: .darkAqua)
        defer { app.appearance = previousAppearance }

        let scene = ScreenshotBackdrop(frame: NSRect(x: 0, y: 0, width: 1320, height: 340))
        let panel = TaskbarPanel(
            contentRect: NSRect(x: 100, y: 100, width: 1320, height: 340),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.contentView = scene
        defer { panel.close() }
        let bar = BarView(frame: NSRect(x: 0, y: 8, width: 1320, height: BarLayout.height))
        let samples = sampleWindows()
        let launchers = dockLaunchers()
        bar.update(entries: samples, trusted: true, launchers: launchers)
        scene.addSubview(bar)
        scene.layoutSubtreeIfNeeded()
        try writeView(scene, to: directory.appendingPathComponent("overview.png"))
        try writeView(bar, to: directory.appendingPathComponent("windowbar.png"))

        guard let chrome = launchers.first(where: { $0.name == "Google Chrome" }) else { return }
        let menu = LauncherMenuBuilder(profiles: SampleChromeProfiles()).makeMenu(
            launcher: chrome, windows: samples.filter { $0.appName == chrome.name }, onSelect: { _ in })
        let capture = MenuCapture(
            app: app, menu: menu, destination: directory.appendingPathComponent("chrome-menu.png"))
        let timer = Timer(
            timeInterval: 0.25, target: capture, selector: #selector(MenuCapture.capture), userInfo: nil,
            repeats: false)
        RunLoop.main.add(timer, forMode: .eventTracking)
        menu.popUp(positioning: nil, at: NSPoint(x: 250, y: 700), in: nil)
        if let failure = capture.failure { throw failure }
        guard capture.captured else { throw RenderingError.bitmapUnavailable }
    }

    private final class MenuCapture: NSObject {
        let app: NSApplication
        let menu: NSMenu
        let destination: URL
        var failure: Error?
        var captured = false

        init(app: NSApplication, menu: NSMenu, destination: URL) {
            self.app = app
            self.menu = menu
            self.destination = destination
        }

        @objc func capture(_ timer: Timer) {
            defer { menu.cancelTracking() }
            do {
                guard let view = app.windows.first(where: { $0.level == .popUpMenu })?.contentView else {
                    throw RenderingError.bitmapUnavailable
                }
                try PreviewRenderer.writeView(view, to: destination, opaqueMenu: true)
                captured = true
            } catch { failure = error }
        }
    }

    private static func writeView(_ view: NSView, to url: URL, opaqueMenu: Bool = false) throws {
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            throw RenderingError.bitmapUnavailable
        }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let output: NSBitmapImageRep
        if opaqueMenu {
            // Vibrancy's backdrop is not part of an owned view snapshot. Supply
            // a flat menu backing while preserving the native menu foreground.
            let image = NSImage(size: view.bounds.size)
            image.lockFocus()
            NSColor(calibratedWhite: 0.14, alpha: 1).setFill()
            NSBezierPath(roundedRect: NSRect(origin: .zero, size: view.bounds.size), xRadius: 8, yRadius: 8)
                .fill()
            bitmap.draw(in: NSRect(origin: .zero, size: view.bounds.size))
            image.unlockFocus()
            guard let data = image.tiffRepresentation, let result = NSBitmapImageRep(data: data) else {
                throw RenderingError.bitmapUnavailable
            }
            output = result
        } else {
            output = bitmap
        }
        guard let png = output.representation(using: .png, properties: [:]) else {
            throw RenderingError.bitmapUnavailable
        }
        try png.write(to: url)
    }
}

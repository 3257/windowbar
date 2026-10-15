import AppKit
import WindowBarCore

enum WindowWorkAreaVerification {
    final class Backend: DesktopWindowResizing {
        var states: [String: DesktopWindowState] = [:]
        var writes: [CGRect] = []
        var rejectsWrites = false
        func state(of entry: WindowEntry) -> DesktopWindowState? { states[entry.id] }
        func setFrame(_ frame: CGRect, of entry: WindowEntry) -> Bool {
            guard !rejectsWrites else { return false }
            writes.append(frame)
            states[entry.id]?.frame = frame
            return true
        }
    }

    static func run() throws {
        let require = FeatureVerification.require
        let backend = Backend()
        let controller = WindowWorkAreaController(backend: backend)
        var entry = sampleWindows()[0]
        let full = CGRect(x: 0, y: 0, width: 1440, height: 870)
        let normal = CGRect(x: 120, y: 140, width: 1000, height: 600)
        let area = ReservedWindowArea(
            displayID: 1, visibleFrame: full,
            barFrame: CGRect(x: 12, y: 8, width: 1416, height: 66))
        let fitted = area.fittedFrame(for: full)!
        func scan(_ frame: CGRect, areas: [ReservedWindowArea] = [area], mouseDown: Bool = false) {
            entry.frame = frame
            controller.update(entries: [entry], areas: areas, mouseDown: mouseDown, now: 1)
        }
        backend.states[entry.id] = DesktopWindowState(frame: normal)
        scan(normal)
        try require(backend.writes.isEmpty, "An ordinary window was resized")
        backend.states[entry.id]?.frame = full
        scan(full, mouseDown: true)
        try require(backend.writes.isEmpty, "Reservation interrupted a mouse drag")
        scan(full)
        try require(backend.writes == [fitted], "Maximized window did not end above the shelf")
        scan(fitted)
        try require(backend.writes.count == 1, "Unchanged reservation kept resizing the window")
        scan(fitted, areas: [])
        try require(backend.writes.last == full, "Hiding/auto-hiding the bar did not restore the window")
        backend.states[entry.id]?.frame = full
        scan(full)
        backend.states[entry.id]?.frame = normal
        scan(normal)
        let beforeManual = backend.writes.count
        controller.restoreAll()
        try require(backend.writes.count == beforeManual, "Quit overwrote a manual resize")

        backend.states[entry.id] = DesktopWindowState(frame: full, fullScreen: true)
        scan(full)
        try require(backend.writes.count == beforeManual, "Native fullscreen was resized")
        backend.states[entry.id] = DesktopWindowState(frame: full, minimized: true)
        scan(full)
        try require(backend.writes.count == beforeManual, "A minimized window was resized")
        backend.states[entry.id] = DesktopWindowState(frame: full)
        backend.rejectsWrites = true
        scan(full)
        controller.restoreAll()
        try require(backend.writes.count == beforeManual, "Rejected resize was tracked as successful")
        backend.rejectsWrites = false
        scan(full)
        controller.restoreAll()
        try require(backend.writes.last == full, "Quit did not restore its own unchanged reservation")

        // AX sizing changes Chrome's native zoom state; the next titlebar double-click must restore.
        backend.states[entry.id]?.frame = normal
        scan(normal)
        backend.states[entry.id]?.frame = full
        scan(full)
        controller.requestRestore(id: entry.id, pointer: CGPoint(x: 400, y: 850), now: 1)
        backend.states[entry.id]?.frame = full
        scan(full)
        try require(backend.writes.last == normal, "Second titlebar double-click did not restore normal size")

        // A double-click in page content must not behave like a titlebar restore.
        backend.states[entry.id]?.frame = full
        scan(full)
        controller.requestRestore(id: entry.id, pointer: CGPoint(x: 400, y: 300), now: 1)
        backend.states[entry.id]?.frame = full
        scan(full)
        try require(backend.writes.last == fitted, "A content double-click restored the window")
        controller.restoreAll()
        print(
            "PASS: maximized-window clearance, drag/manual-resize protection, hide/quit restoration, native fullscreen/minimized exclusions, rejected writes and titlebar maximize/restore"
        )
    }
}

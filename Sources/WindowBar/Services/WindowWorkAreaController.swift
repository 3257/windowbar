import AppKit
import ApplicationServices
import WindowBarCore

struct DesktopWindowState {
    var frame: CGRect
    var fullScreen = false
    var minimized = false
}

protocol DesktopWindowResizing {
    func state(of entry: WindowEntry) -> DesktopWindowState?
    @discardableResult func setFrame(_ frame: CGRect, of entry: WindowEntry) -> Bool
}

struct AccessibilityWindowResizer: DesktopWindowResizing {
    func state(of entry: WindowEntry) -> DesktopWindowState? {
        guard let window = entry.element,
            let position = attribute(window, kAXPositionAttribute),
            let extent = attribute(window, kAXSizeAttribute),
            CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(extent) == AXValueGetTypeID()
        else { return nil }
        var point = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(unsafeBitCast(position, to: AXValue.self), .cgPoint, &point),
            AXValueGetValue(unsafeBitCast(extent, to: AXValue.self), .cgSize, &size)
        else { return nil }
        return DesktopWindowState(
            frame: DisplayFilter.cocoaFrame(
                accessibilityFrame: CGRect(origin: point, size: size),
                primaryDisplayTop: CGDisplayBounds(CGMainDisplayID()).height),
            fullScreen: attribute(window, "AXFullScreen") as? Bool ?? false,
            minimized: attribute(window, kAXMinimizedAttribute) as? Bool ?? entry.minimized)
    }

    func setFrame(_ frame: CGRect, of entry: WindowEntry) -> Bool {
        guard let window = entry.element, let current = state(of: entry), !current.fullScreen else {
            return false
        }
        var settable: DarwinBoolean = false
        guard AXUIElementIsAttributeSettable(window, kAXSizeAttribute as CFString, &settable) == .success,
            settable.boolValue
        else { return false }
        let top = CGDisplayBounds(CGMainDisplayID()).height
        var position = CGPoint(x: frame.minX, y: top - frame.maxY)
        var size = frame.size
        let moves = abs(frame.minX - current.frame.minX) > 1 || abs(frame.maxY - current.frame.maxY) > 1
        if moves {
            guard
                AXUIElementIsAttributeSettable(window, kAXPositionAttribute as CFString, &settable)
                    == .success, settable.boolValue
            else { return false }
        }
        guard let sizeValue = AXValueCreate(.cgSize, &size),
            AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue) == .success
        else { return false }
        if moves, let pointValue = AXValueCreate(.cgPoint, &position) {
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, pointValue)
        }
        guard let actual = state(of: entry), ReservedWindowArea.matches(actual.frame, frame) else {
            // A size constraint or partial write must not leave an unintended move behind.
            var oldSize = current.frame.size
            var oldPoint = CGPoint(x: current.frame.minX, y: top - current.frame.maxY)
            if let value = AXValueCreate(.cgSize, &oldSize) {
                AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, value)
            }
            if moves, let value = AXValueCreate(.cgPoint, &oldPoint) {
                AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value)
            }
            return false
        }
        return true
    }
}

/// Access only on the window scanner queue. Re-read live frames before every write.
final class WindowWorkAreaController {
    private struct Managed {
        let entry: WindowEntry
        let original: CGRect
        var applied: CGRect
        let displayID: UInt32
        let restoreFrame: CGRect
    }
    private let backend: DesktopWindowResizing
    private var managed: [String: Managed] = [:]
    private var normalFrames: [String: CGRect] = [:]
    private var restoreRequests: [String: TimeInterval] = [:]

    init(backend: DesktopWindowResizing = AccessibilityWindowResizer()) { self.backend = backend }

    func requestRestore(id: String, pointer: CGPoint, now: TimeInterval) {
        guard let record = managed[id],
            CGRect(
                x: record.applied.minX, y: record.applied.maxY - 44,
                width: record.applied.width, height: 44
            ).contains(pointer)
        else { return }
        restoreRequests[id] = now
    }

    func update(
        entries: [WindowEntry], areas: [ReservedWindowArea], mouseDown: Bool = false,
        now: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) {
        guard !mouseDown else { return }
        let available = Set(entries.map(\.id))
        managed = managed.filter { available.contains($0.key) }
        normalFrames = normalFrames.filter { available.contains($0.key) }
        restoreRequests = restoreRequests.filter { available.contains($0.key) && now - $0.value <= 3 }
        for entry in entries {
            // Avoid extra AX traffic for ordinary windows unless a managed frame needs restoring.
            let candidate = areas.first { $0.fittedFrame(for: entry.frame ?? .zero) != nil }
            guard managed[entry.id] != nil || candidate != nil else {
                if let frame = entry.frame, !entry.minimized, !areas.isEmpty {
                    normalFrames[entry.id] = frame
                }
                continue
            }
            guard let state = backend.state(of: entry), !state.minimized else { continue }
            guard !state.fullScreen else {
                managed.removeValue(forKey: entry.id)
                restoreRequests.removeValue(forKey: entry.id)
                continue
            }
            if let record = managed[entry.id] {
                if restoreRequests[entry.id] != nil,
                    areas.contains(where: { $0.fittedFrame(for: state.frame) != nil })
                {
                    if backend.setFrame(record.restoreFrame, of: entry) {
                        managed.removeValue(forKey: entry.id)
                        restoreRequests.removeValue(forKey: entry.id)
                        normalFrames[entry.id] = record.restoreFrame
                    }
                    continue
                }
                if ReservedWindowArea.matches(state.frame, record.applied) {
                    let target = areas.first { $0.displayID == record.displayID }?
                        .fittedFrame(for: record.original)
                    if let target {
                        if !ReservedWindowArea.matches(target, state.frame),
                            backend.setFrame(target, of: entry)
                        {
                            managed[entry.id]?.applied = target
                        }
                    } else if backend.setFrame(record.original, of: entry) {
                        managed.removeValue(forKey: entry.id)
                    }
                    continue
                }
                // A manual move/resize owns the frame from here on.
                managed.removeValue(forKey: entry.id)
            }
            guard let area = areas.first(where: { $0.fittedFrame(for: state.frame) != nil }),
                let target = area.fittedFrame(for: state.frame)
            else {
                normalFrames[entry.id] = state.frame
                continue
            }
            let knownNormal = normalFrames[entry.id].flatMap { frame in
                area.visibleFrame.contains(frame)
                    && !ReservedWindowArea.matches(frame, area.visibleFrame, tolerance: 8) ? frame : nil
            }
            let restored = knownNormal ?? ReservedWindowArea.defaultRestoredFrame(in: target)
            if backend.setFrame(target, of: entry) {
                managed[entry.id] = Managed(
                    entry: entry, original: state.frame, applied: target, displayID: area.displayID,
                    restoreFrame: restored)
            }
        }
    }

    func restoreAll() {
        for (id, record) in managed {
            guard let state = backend.state(of: record.entry) else { continue }
            if state.fullScreen || !ReservedWindowArea.matches(state.frame, record.applied)
                || backend.setFrame(record.original, of: record.entry)
            {
                managed.removeValue(forKey: id)
            }
        }
        restoreRequests = [:]
    }
}

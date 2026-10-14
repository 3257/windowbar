import AppKit

class ReorderableButton: NSButton, NSDraggingSource {
    enum Kind: String { case window, launcher }
    var dragIdentifier = ""
    var kind: Kind = .window
    var onReorder: ((String, String, Bool) -> Void)?
    var onDragStart: (() -> Void)?
    private var dropHighlight = false
    private var type: NSPasteboard.PasteboardType {
        NSPasteboard.PasteboardType("local.windowbar.\(kind.rawValue)")
    }

    func configureReordering(id: String, kind: Kind) {
        dragIdentifier = id
        self.kind = kind
        registerForDraggedTypes([type])
    }

    override func mouseDown(with event: NSEvent) {
        let start = convert(event.locationInWindow, from: nil)
        guard isEnabled else { return }
        highlight(true)
        defer { highlight(false) }
        while let next = window?.nextEvent(
            matching: [.leftMouseDragged, .leftMouseUp], until: .distantFuture, inMode: .eventTracking,
            dequeue: true)
        {
            let point = convert(next.locationInWindow, from: nil)
            if next.type == .leftMouseUp {
                if bounds.contains(point) { performClick(nil) }
                return
            }
            if hypot(point.x - start.x, point.y - start.y) > 5 {
                onDragStart?()
                let item = NSPasteboardItem()
                item.setString(dragIdentifier, forType: type)
                let dragging = NSDraggingItem(pasteboardWriter: item)
                let image = NSImage(size: bounds.size)
                if let bitmap = bitmapImageRepForCachingDisplay(in: bounds) {
                    cacheDisplay(in: bounds, to: bitmap)
                    image.addRepresentation(bitmap)
                }
                dragging.setDraggingFrame(bounds, contents: image)
                beginDraggingSession(with: [dragging], event: next, source: self)
                return
            }
        }
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext)
        -> NSDragOperation
    {
        context == .withinApplication ? .move : []
    }

    private func accepts(_ sender: NSDraggingInfo) -> Bool {
        guard let source = sender.draggingSource as? ReorderableButton,
            source.kind == kind, source.dragIdentifier != dragIdentifier,
            sender.draggingPasteboard.string(forType: type) == source.dragIdentifier
        else { return false }
        return true
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        dropHighlight = accepts(sender)
        needsDisplay = true
        return dropHighlight ? .move : []
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { draggingEntered(sender) }
    override func draggingExited(_ sender: NSDraggingInfo?) {
        dropHighlight = false
        needsDisplay = true
    }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { accepts(sender) }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        defer {
            dropHighlight = false
            needsDisplay = true
        }
        guard accepts(sender), let id = sender.draggingPasteboard.string(forType: type) else { return false }
        let point = convert(sender.draggingLocation, from: nil)
        onReorder?(id, dragIdentifier, point.x > bounds.midX)
        return true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        drawDropHighlight()
    }

    func drawDropHighlight() {
        guard dropHighlight else { return }
        NSColor.controlAccentColor.setStroke()
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 9, yRadius: 9)
        path.lineWidth = 2
        path.stroke()
    }
}

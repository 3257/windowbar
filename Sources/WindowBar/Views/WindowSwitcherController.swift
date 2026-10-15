import AppKit
import WindowBarCore

final class WindowSwitcherController: NSWindowController, NSSearchFieldDelegate, NSTableViewDataSource,
    NSTableViewDelegate, NSWindowDelegate
{
    let search = NSSearchField()
    let table = WindowSwitcherTable()
    let emptyLabel = NSTextField(labelWithString: "No matching windows")
    private var entries: [WindowEntry] = []
    private(set) var results: [WindowEntry] = []
    private var preferences = BarPreferences()
    var onSelect: ((WindowEntry) -> Void)?
    var onCancel: (() -> Void)?

    init(decorateWindow: Bool = true) {
        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 420),
            styleMask: decorateWindow ? [.titled, .closable] : [.borderless], backing: .buffered, defer: false
        )
        window.title = "Search Windows"
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.contentView = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 420))
        super.init(window: window)
        window.delegate = self
        search.frame = NSRect(x: 20, y: 366, width: 560, height: 30)
        search.placeholderString = "Window title, app, or Chrome profile"
        search.delegate = self
        search.sendsSearchStringImmediately = true
        window.contentView?.addSubview(search)
        let scroll = NSScrollView(frame: NSRect(x: 20, y: 42, width: 560, height: 308))
        scroll.hasVerticalScroller = true
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("window"))
        column.width = 540
        table.addTableColumn(column)
        table.headerView = nil
        table.rowHeight = 48
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.doubleAction = #selector(chooseSelection)
        table.onCommand = { [weak self] in self?.handleCommand($0) ?? false }
        scroll.documentView = table
        window.contentView?.addSubview(scroll)
        emptyLabel.frame = NSRect(x: 30, y: 210, width: 530, height: 24)
        emptyLabel.textColor = .secondaryLabelColor
        window.contentView?.addSubview(emptyLabel)
        let hint = NSTextField(labelWithString: "↑ ↓ to choose · Return to switch · Escape to dismiss")
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        hint.frame = NSRect(x: 24, y: 14, width: 540, height: 20)
        window.contentView?.addSubview(hint)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(entries: [WindowEntry], preferences: BarPreferences) {
        self.entries = entries
        self.preferences = preferences
        if !preferences.searchEnabled {
            dismiss()
            results = []
            table.reloadData()
            return
        }
        filter()
    }

    func present() {
        guard preferences.searchEnabled else { return }
        search.stringValue = ""
        filter()
        window?.center()
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(search)
    }

    func dismiss() { window?.orderOut(nil) }
    func windowDidResignKey(_ notification: Notification) { dismiss() }
    func controlTextDidChange(_ obj: Notification) { filter() }

    func filter() {
        let selected = results.indices.contains(table.selectedRow) ? results[table.selectedRow].id : nil
        let ids = Set(
            WindowSearch.filter(
                entries.map {
                    SearchableWindow(
                        id: $0.id, title: $0.title, app: $0.appName,
                        profile: $0.profile?.name ?? "", minimized: $0.minimized)
                }, query: search.stringValue, includeMinimized: preferences.searchIncludesMinimized))
        results = entries.filter { ids.contains($0.id) }
        table.reloadData()
        emptyLabel.isHidden = !results.isEmpty
        let row = selected.flatMap { id in results.firstIndex { $0.id == id } } ?? (results.isEmpty ? -1 : 0)
        table.selectRowIndexes(row < 0 ? [] : IndexSet(integer: row), byExtendingSelection: false)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        handleCommand(commandSelector)
    }

    @discardableResult func handleCommand(_ command: Selector) -> Bool {
        switch command {
        case #selector(NSResponder.insertNewline(_:)): chooseSelection()
        case #selector(NSResponder.cancelOperation(_:)):
            dismiss()
            onCancel?()
        case #selector(NSResponder.moveDown(_:)): moveSelection(1)
        case #selector(NSResponder.moveUp(_:)): moveSelection(-1)
        default: return false
        }
        return true
    }
    private func moveSelection(_ direction: Int) {
        guard !results.isEmpty else { return }
        let row = min(results.count - 1, max(0, table.selectedRow + direction))
        table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        table.scrollRowToVisible(row)
    }
    @objc func chooseSelection() {
        guard results.indices.contains(table.selectedRow) else { return }
        let entry = results[table.selectedRow]
        dismiss()
        onSelect?(entry)
    }
    func windowWillClose(_ notification: Notification) { onCancel?() }
    func numberOfRows(in tableView: NSTableView) -> Int { results.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard results.indices.contains(row) else { return nil }
        let entry = results[row]
        let cell = NSTableCellView(frame: NSRect(x: 0, y: 0, width: 540, height: 48))
        let icon = NSImageView(frame: NSRect(x: 8, y: 10, width: 28, height: 28))
        icon.image = entry.icon
        cell.addSubview(icon)
        let title = NSTextField(labelWithString: entry.title)
        title.lineBreakMode = .byTruncatingTail
        title.frame = NSRect(x: 48, y: 25, width: 480, height: 18)
        cell.addSubview(title)
        let detail = NSTextField(
            labelWithString: entry.appName + (entry.profile.map { " · \($0.name)" } ?? "")
                + (entry.minimized ? " · Minimized" : ""))
        detail.textColor = .secondaryLabelColor
        detail.font = .systemFont(ofSize: 11)
        detail.frame = NSRect(x: 48, y: 6, width: 480, height: 16)
        cell.addSubview(detail)
        cell.setAccessibilityLabel(title.stringValue + " · " + detail.stringValue)
        return cell
    }
}

final class WindowSwitcherTable: NSTableView {
    var onCommand: ((Selector) -> Bool)?
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 || event.keyCode == 76 {
            if onCommand?(#selector(NSResponder.insertNewline(_:))) == true { return }
        } else if event.keyCode == 53 {
            if onCommand?(#selector(NSResponder.cancelOperation(_:))) == true { return }
        }
        super.keyDown(with: event)
    }
}

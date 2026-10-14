import AppKit
import WindowBarCore

final class ShortcutRecorderButton: NSButton {
    var binding: ShortcutBinding {
        didSet { title = Self.label(binding) }
    }
    var onRecord: ((ShortcutBinding) throws -> Void)?
    var onError: ((Error) -> Void)?
    private var recording = false

    init(binding: ShortcutBinding) {
        self.binding = binding
        super.init(frame: .zero)
        bezelStyle = .rounded
        title = Self.label(binding)
        target = self
        action = #selector(record)
        setAccessibilityLabel("Record shortcut for \(binding.action.rawValue)")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var acceptsFirstResponder: Bool { true }

    @objc private func record() {
        recording = true
        title = "Press a shortcut…"
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        guard recording else {
            super.keyDown(with: event)
            return
        }
        if event.keyCode == 53 {
            recording = false
            title = Self.label(binding)
            return
        }
        var modifiers: UInt32 = 0
        if event.modifierFlags.contains(.command) { modifiers |= ShortcutBinding.command }
        if event.modifierFlags.contains(.control) { modifiers |= ShortcutBinding.control }
        if event.modifierFlags.contains(.option) { modifiers |= ShortcutBinding.option }
        if event.modifierFlags.contains(.shift) { modifiers |= ShortcutBinding.shift }
        let updated = ShortcutBinding(
            action: binding.action, keyCode: UInt32(event.keyCode), modifiers: modifiers)
        do {
            try ShortcutBinding.validate([updated])
            try onRecord?(updated)
            binding = updated
        } catch { onError?(error) }
        recording = false
        title = Self.label(binding)
    }

    static func label(_ binding: ShortcutBinding) -> String {
        var text = ""
        if binding.modifiers & ShortcutBinding.control != 0 { text += "⌃" }
        if binding.modifiers & ShortcutBinding.option != 0 { text += "⌥" }
        if binding.modifiers & ShortcutBinding.shift != 0 { text += "⇧" }
        if binding.modifiers & ShortcutBinding.command != 0 { text += "⌘" }
        let special: [UInt32: String] = [
            123: "←", 124: "→", 125: "↓", 126: "↑", 36: "↩", 48: "⇥", 49: "Space", 51: "⌫",
        ]
        let key: String
        if let value = special[binding.keyCode] {
            key = value
        } else if let event = CGEvent(
            keyboardEventSource: nil, virtualKey: CGKeyCode(binding.keyCode), keyDown: true)
        {
            event.flags = []
            key = NSEvent(cgEvent: event)?.charactersIgnoringModifiers?.uppercased() ?? "\(binding.keyCode)"
        } else {
            key = "\(binding.keyCode)"
        }
        return text + key
    }
}

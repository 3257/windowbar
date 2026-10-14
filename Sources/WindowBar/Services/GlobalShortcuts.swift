import Carbon
import Foundation
import WindowBarCore

protocol HotKeyBackend: AnyObject {
    var onPressed: ((UInt32) -> Void)? { get set }
    func register(_ binding: ShortcutBinding, identifier: UInt32) throws
    func unregisterAll()
}

final class CarbonHotKeyBackend: HotKeyBackend {
    var onPressed: ((UInt32) -> Void)?
    private var references: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?
    private static let signature: OSType = 0x5742_5231

    init() {
        var event = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, context in
                guard let event, let context else { return OSStatus(eventNotHandledErr) }
                var id = EventHotKeyID()
                let status = GetEventParameter(
                    event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                    nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
                guard status == noErr, id.signature == CarbonHotKeyBackend.signature else {
                    return OSStatus(eventNotHandledErr)
                }
                let backend = Unmanaged<CarbonHotKeyBackend>.fromOpaque(context).takeUnretainedValue()
                backend.onPressed?(id.id)
                return noErr
            }, 1, &event, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }

    func register(_ binding: ShortcutBinding, identifier: UInt32) throws {
        guard handler != nil else { throw RegistrationError.unavailable }
        var reference: EventHotKeyRef?
        let id = EventHotKeyID(signature: Self.signature, id: identifier)
        let status = RegisterEventHotKey(
            binding.keyCode, binding.modifiers, id, GetApplicationEventTarget(), 0, &reference)
        guard status == noErr, let reference else { throw RegistrationError.conflict }
        references.append(reference)
    }

    func unregisterAll() {
        for reference in references { UnregisterEventHotKey(reference) }
        references.removeAll()
    }

    deinit {
        unregisterAll()
        if let handler { RemoveEventHandler(handler) }
    }

    enum RegistrationError: LocalizedError {
        case conflict, unavailable
        var errorDescription: String? {
            self == .conflict
                ? "A shortcut is already in use. Choose another combination."
                : "Global shortcuts are unavailable in this session."
        }
    }
}

final class GlobalShortcuts {
    private let backend: HotKeyBackend
    private(set) var bindings: [ShortcutBinding] = []
    var onAction: ((ShortcutAction) -> Void)?

    init(backend: HotKeyBackend = CarbonHotKeyBackend()) {
        self.backend = backend
        backend.onPressed = { [weak self] id in
            guard let self, id > 0, Int(id) <= self.bindings.count else { return }
            self.onAction?(self.bindings[Int(id) - 1].action)
        }
    }

    /// Roll back to the previous shortcuts if the OS rejects a new combination.
    func configure(_ updated: [ShortcutBinding]) throws {
        try ShortcutBinding.validate(updated)
        if updated == bindings { return }
        let previous = bindings
        backend.unregisterAll()
        do {
            try install(updated)
            bindings = updated
        } catch {
            backend.unregisterAll()
            if (try? install(previous)) == nil {
                backend.unregisterAll()
                bindings = []
            } else {
                bindings = previous
            }
            throw error
        }
    }

    private func install(_ values: [ShortcutBinding]) throws {
        for (index, binding) in values.enumerated() {
            try backend.register(binding, identifier: UInt32(index + 1))
        }
    }
}

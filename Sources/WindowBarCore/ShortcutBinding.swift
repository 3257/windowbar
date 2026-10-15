import Foundation

public enum ShortcutAction: String, CaseIterable, Codable {
    case nextWindow, previousWindow
    case pinned1, pinned2, pinned3, pinned4, pinned5, pinned6, pinned7, pinned8, pinned9
    case searchWindows

    public var pinnedIndex: Int? {
        guard rawValue.hasPrefix("pinned"), let number = Int(rawValue.dropFirst(6)) else { return nil }
        return number - 1
    }
}

public struct ShortcutBinding: Equatable, Codable {
    public var action: ShortcutAction
    public var keyCode: UInt32
    public var modifiers: UInt32

    // Carbon's public hot-key modifier masks, kept platform-independent for tests.
    public static let command: UInt32 = 256
    public static let shift: UInt32 = 512
    public static let option: UInt32 = 2048
    public static let control: UInt32 = 4096
    public static let allowedModifiers = command | shift | option | control

    public init(action: ShortcutAction, keyCode: UInt32, modifiers: UInt32) {
        self.action = action
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    public static let defaults: [ShortcutBinding] = {
        let modifiers = control | command
        let digits: [UInt32] = [18, 19, 20, 21, 23, 22, 26, 28, 25]
        return [
            ShortcutBinding(action: .nextWindow, keyCode: 124, modifiers: modifiers),
            ShortcutBinding(action: .previousWindow, keyCode: 123, modifiers: modifiers),
        ]
            + zip(ShortcutAction.allCases.filter { $0.pinnedIndex != nil }, digits).map {
                ShortcutBinding(action: $0, keyCode: $1, modifiers: modifiers)
            }
            + [ShortcutBinding(action: .searchWindows, keyCode: 49, modifiers: modifiers)]
    }()

    public enum ValidationError: Error, Equatable { case unsafeKey, duplicateKey, duplicateAction }

    public static func validate(_ bindings: [ShortcutBinding]) throws {
        var keys = Set<String>()
        var actions = Set<ShortcutAction>()
        for binding in bindings {
            guard binding.keyCode < 128,
                binding.modifiers & ~allowedModifiers == 0,
                binding.modifiers & (command | option | control) != 0,
                ![54, 55, 56, 57, 58, 59, 60, 61, 62, 63].contains(binding.keyCode)
            else { throw ValidationError.unsafeKey }
            guard keys.insert("\(binding.keyCode):\(binding.modifiers)").inserted else {
                throw ValidationError.duplicateKey
            }
            guard actions.insert(binding.action).inserted else { throw ValidationError.duplicateAction }
        }
    }

    public static func cycleIndex(count: Int, focusedIndex: Int?, forward: Bool) -> Int? {
        guard count > 0 else { return nil }
        guard let focusedIndex, (0..<count).contains(focusedIndex) else { return forward ? 0 : count - 1 }
        return (focusedIndex + (forward ? 1 : count - 1)) % count
    }
}

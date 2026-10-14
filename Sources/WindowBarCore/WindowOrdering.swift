import Foundation

/// An explicit order for a changing collection. Missing IDs disappear; new IDs append.
public struct WindowOrdering: Equatable {
    public private(set) var identifiers: [String] = []

    public init() {}

    public mutating func reconcile(_ current: [String]) {
        let available = Set(current)
        identifiers.removeAll { !available.contains($0) }
        var seen = Set(identifiers)
        for id in current where seen.insert(id).inserted { identifiers.append(id) }
    }

    public mutating func move(_ source: String, before target: String) {
        move(source, relativeTo: target, after: false)
    }

    public mutating func move(_ source: String, relativeTo target: String, after: Bool) {
        guard source != target, identifiers.contains(source), identifiers.contains(target) else { return }
        identifiers.removeAll { $0 == source }
        if let index = identifiers.firstIndex(of: target) {
            identifiers.insert(source, at: index + (after ? 1 : 0))
        }
    }
}

import Foundation

public struct WindowRecency {
    public private(set) var identifiers: [String] = []
    public init() {}

    public mutating func update(available: Set<String>, focused: String?) {
        identifiers.removeAll { !available.contains($0) }
        guard let focused, available.contains(focused) else { return }
        identifiers.removeAll { $0 == focused }
        identifiers.insert(focused, at: 0)
    }

    public func mostRecent(in candidates: [String]) -> String? {
        let available = Set(candidates)
        return identifiers.first(where: available.contains) ?? candidates.first
    }
}

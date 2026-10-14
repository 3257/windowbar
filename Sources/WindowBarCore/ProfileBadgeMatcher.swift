import Foundation

public enum ProfileBadgeMatcher {
    /// Only match Chrome's profile-control text, never a page/window title.
    public static func match(controlText: String, profiles: [ChromeProfile]) -> ChromeProfile? {
        let text = controlText.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidates = profiles.filter {
            text == $0.name || text == "Profile: \($0.name)" || text == "Profile (\($0.name))"
        }
        return candidates.count == 1 ? candidates.first : nil
    }

    public static func colorIndex(directory: String, count: Int = 6) -> Int {
        guard count > 0 else { return 0 }
        let hash = directory.utf8.reduce(UInt64(5381)) { ($0 &* 33) &+ UInt64($1) }
        return Int(hash % UInt64(count))
    }
}

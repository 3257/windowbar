import Foundation

public enum ProfileBadgeMatcher {
    /// Only match Chrome's profile-control text, never a page/window title.
    public static func match(controlText: String, profiles: [ChromeProfile]) -> ChromeProfile? {
        let text = controlText.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidates = profiles.filter {
            text == $0.name || text == "Profile: \($0.name)" || text == "Profile (\($0.name))"
                || (text.hasSuffix(" (\($0.name))") && text.count > $0.name.count + 3)
        }
        return candidates.count == 1 ? candidates.first : nil
    }

    /// Chrome's Profiles menu can append an account in parentheses to a profile name.
    public static func matchMenuItem(_ title: String, profiles: [ChromeProfile]) -> ChromeProfile? {
        let text = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidates = profiles.filter {
            text == $0.name || (text.hasPrefix($0.name + " (") && text.hasSuffix(")"))
        }
        return candidates.count == 1 ? candidates.first : nil
    }

    public static func colorIndex(directory: String, count: Int = 6) -> Int {
        guard count > 0 else { return 0 }
        let hash = directory.utf8.reduce(UInt64(5381)) { ($0 &* 33) &+ UInt64($1) }
        return Int(hash % UInt64(count))
    }
}

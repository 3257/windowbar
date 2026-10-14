import Foundation

public struct ChromeProfile: Equatable {
    public let directory: String
    public let name: String
    public let lastUsed: Bool

    public init(directory: String, name: String, lastUsed: Bool = false) {
        self.directory = directory
        self.name = name
        self.lastUsed = lastUsed
    }

    /// Parse only profile display metadata; Chrome remains the owner of this file.
    public static func decodeLocalState(_ data: Data) throws -> [ChromeProfile] {
        let state = try JSONDecoder().decode(LocalState.self, from: data)
        let cache = state.profile?.infoCache ?? [:]
        return cache.compactMap { directory, metadata in
            guard validDirectory(directory), !metadata.omitted, !metadata.ephemeral else { return nil }
            let name = metadata.name?.trimmingCharacters(in: .whitespacesAndNewlines)
            return ChromeProfile(
                directory: directory, name: name?.isEmpty == false ? name ?? directory : directory,
                lastUsed: directory == state.profile?.lastUsed)
        }.sorted {
            let comparison = $0.name.localizedCaseInsensitiveCompare($1.name)
            return comparison == .orderedSame ? $0.directory < $1.directory : comparison == .orderedAscending
        }
    }

    public static func validDirectory(_ directory: String) -> Bool {
        !directory.isEmpty && ![".", "..", "Guest Profile", "System Profile"].contains(directory)
            && directory.rangeOfCharacter(from: CharacterSet(charactersIn: "/\\\0\n\r")) == nil
    }

    public var launchArguments: [String] {
        [
            "--profile-directory=\(directory)", "--ignore-profile-directory-if-not-exists", "--new-window",
            "about:blank",
        ]
    }
}

private struct LocalState: Decodable {
    let profile: Profiles?
    struct Profiles: Decodable {
        let infoCache: [String: Metadata]?
        let lastUsed: String?
        enum CodingKeys: String, CodingKey {
            case infoCache = "info_cache"
            case lastUsed = "last_used"
        }
    }
    struct Metadata: Decodable {
        let name: String?
        let omitted: Bool
        let ephemeral: Bool
        enum CodingKeys: String, CodingKey {
            case name
            case omitted = "is_omitted"
            case ephemeral = "is_ephemeral"
        }
        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            name = try values.decodeIfPresent(String.self, forKey: .name)
            omitted = try values.decodeIfPresent(Bool.self, forKey: .omitted) ?? false
            ephemeral = try values.decodeIfPresent(Bool.self, forKey: .ephemeral) ?? false
        }
    }
}

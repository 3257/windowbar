import Foundation

/// A missing preference is different from a preference set to false or zero.
public struct DockSnapshot: Codable, Equatable {
    public let token: String
    public let ownerPID: Int32
    public let autohide: Bool?
    public let delay: Double?

    public init(token: String, ownerPID: Int32, autohide: Bool?, delay: Double?) {
        self.token = token
        self.ownerPID = ownerPID
        self.autohide = autohide
        self.delay = delay
    }

    private enum CodingKeys: String, CodingKey {
        case token
        case ownerPID = "pid"
        case autohide
        case delay = "autohide-delay"
    }
}

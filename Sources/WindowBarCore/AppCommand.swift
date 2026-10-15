import Foundation

public enum AppCommand: Equatable {
    case run(demo: Bool, screenshots: Bool)
    case diagnose
    case preview(path: String)
    case screenshots(path: String)
    case guardDock(pid: Int32, token: String)
    case help
    case selfTest
    case install
    case settings

    public enum UsageError: Error { case invalidArguments }

    public static func parse(_ arguments: [String]) throws -> AppCommand {
        switch arguments {
        case []: return .run(demo: false, screenshots: false)
        case ["--demo"]: return .run(demo: true, screenshots: false)
        case ["--screenshot-demo"]: return .run(demo: true, screenshots: true)
        case ["--diagnose"]: return .diagnose
        case ["--help"], ["-h"]: return .help
        case ["--self-test"]: return .selfTest
        case ["--install"]: return .install
        case ["--settings"]: return .settings
        default:
            if arguments.count == 2, arguments[0] == "--render-preview", !arguments[1].isEmpty {
                return .preview(path: arguments[1])
            }
            if arguments.count == 2, arguments[0] == "--render-screenshots", !arguments[1].isEmpty {
                return .screenshots(path: arguments[1])
            }
            if arguments.count == 3, arguments[0] == "--dock-guard", let pid = Int32(arguments[1]), pid > 0,
                !arguments[2].isEmpty
            {
                return .guardDock(pid: pid, token: arguments[2])
            }
            throw UsageError.invalidArguments
        }
    }
}

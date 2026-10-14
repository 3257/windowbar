import Foundation
import ServiceManagement

enum StartupStatus: Equatable {
    case disabled, enabled, requiresApproval, unavailable, needsInstallation
}

protocol LoginItemBackend {
    var status: StartupStatus { get }
    func register() throws
    func unregister() throws
}

struct NativeLoginItemBackend: LoginItemBackend {
    var status: StartupStatus {
        switch SMAppService.mainApp.status {
        case .enabled: return .enabled
        case .requiresApproval: return .requiresApproval
        case .notRegistered: return .disabled
        case .notFound: return .unavailable
        @unknown default: return .unavailable
        }
    }
    func register() throws { try SMAppService.mainApp.register() }
    func unregister() throws { try SMAppService.mainApp.unregister() }
}

final class LoginItemService {
    private let backend: LoginItemBackend
    private let installed: () -> Bool

    init(
        backend: LoginItemBackend = NativeLoginItemBackend(),
        installed: @escaping () -> Bool = {
            let bundle = Bundle.main.bundleURL.resolvingSymlinksInPath()
            let parents = [
                URL(fileURLWithPath: "/Applications"),
                FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications"),
            ]
            return parents.contains { bundle.deletingLastPathComponent() == $0.resolvingSymlinksInPath() }
        }
    ) {
        self.backend = backend
        self.installed = installed
    }

    var status: StartupStatus { installed() ? backend.status : .needsInstallation }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            guard installed() else { throw ServiceError.installFirst }
            if backend.status != .enabled && backend.status != .requiresApproval { try backend.register() }
        } else if [.enabled, .requiresApproval].contains(backend.status) {
            try backend.unregister()
        }
    }

    enum ServiceError: LocalizedError {
        case installFirst
        var errorDescription: String? { "Install WindowBar in Applications and open that copy first." }
    }
}

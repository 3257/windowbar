import Darwin
import Foundation

/// Kernel-owned lock released even after SIGKILL; child processes must not inherit it.
final class InstanceLock {
    private let descriptor: Int32

    init(directory: URL, name: String = "instance.lock", waits: Bool = false) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let path = directory.appendingPathComponent(name).path
        descriptor = open(path, O_CREAT | O_RDWR | O_CLOEXEC, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw POSIXError(.EACCES) }
        guard flock(descriptor, waits ? LOCK_EX : LOCK_EX | LOCK_NB) == 0 else {
            close(descriptor)
            throw POSIXError(.EWOULDBLOCK)
        }
    }

    deinit { close(descriptor) }
}

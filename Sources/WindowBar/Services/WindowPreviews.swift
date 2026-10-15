import AppKit
import ScreenCaptureKit

enum PreviewResult {
    case image(NSImage)
    case unavailable
}

protocol WindowPreviewProviding {
    func preview(_ entry: WindowEntry, completion: @escaping (PreviewResult) -> Void)
}

protocol WindowCaptureBackend {
    var hasPermission: Bool { get }
    func capture(_ entry: WindowEntry, completion: @escaping (NSImage?) -> Void)
}

struct ScreenCaptureBackend: WindowCaptureBackend {
    var maximumWidth = 640
    var maximumHeight = 360
    var hasPermission: Bool { CGPreflightScreenCaptureAccess() }

    func capture(_ entry: WindowEntry, completion: @escaping (NSImage?) -> Void) {
        guard let id = entry.windowID else {
            completion(nil)
            return
        }
        SCShareableContent.getExcludingDesktopWindows(true, onScreenWindowsOnly: false) { content, error in
            guard error == nil,
                let window = content?.windows.first(where: {
                    $0.windowID == id && $0.owningApplication?.processID == entry.pid
                })
            else {
                completion(nil)
                return
            }
            let config = SCStreamConfiguration()
            let ratio = max(0.1, window.frame.width / max(1, window.frame.height))
            config.width = min(maximumWidth, max(1, Int(Double(maximumHeight) * ratio)))
            config.height = min(maximumHeight, max(1, Int(Double(config.width) / ratio)))
            config.showsCursor = false
            config.capturesAudio = false
            let filter = SCContentFilter(desktopIndependentWindow: window)
            SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) { image, _ in
                completion(image.map { NSImage(cgImage: $0, size: .zero) })
            }
        }
    }
}

final class WindowPreviews: WindowPreviewProviding {
    private let backend: WindowCaptureBackend
    private var cached: (key: String, image: NSImage, time: Date)?
    private var inFlight = false

    init(backend: WindowCaptureBackend = ScreenCaptureBackend()) { self.backend = backend }

    /// A hover never prompts for permission. Only the explicit Settings button does.
    func preview(_ entry: WindowEntry, completion: @escaping (PreviewResult) -> Void) {
        guard backend.hasPermission, !entry.minimized, entry.windowID != nil else {
            completion(.unavailable)
            return
        }
        if let cached, cached.key == entry.id, Date().timeIntervalSince(cached.time) < 2 {
            completion(.image(cached.image))
            return
        }
        guard !inFlight else {
            completion(.unavailable)
            return
        }
        inFlight = true
        backend.capture(entry) { [weak self] image in
            DispatchQueue.main.async {
                guard let self else { return }
                self.inFlight = false
                if let image {
                    self.cached = (entry.id, image, Date())
                    completion(.image(image))
                } else {
                    completion(.unavailable)
                }
            }
        }
    }
}

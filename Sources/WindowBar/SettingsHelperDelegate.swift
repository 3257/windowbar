import AppKit

final class SettingsHelperDelegate: NSObject, NSApplicationDelegate {
    private let features = FeatureCoordinator()
    private var settings: SettingsWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let controller = SettingsWindowController(features: features)
        controller.onPreferencesChanged = { [weak self] updated in
            guard let self else { return }
            try self.features.preferences.save(updated)
            DistributedNotificationCenter.default().postNotificationName(
                .windowBarPreferencesChanged, object: nil, userInfo: nil, deliverImmediately: true)
        }
        controller.onClose = { NSApp.terminate(nil) }
        settings = controller
        let center = DistributedNotificationCenter.default()
        center.addObserver(self, selector: #selector(present), name: .windowBarSettingsShow, object: nil)
        center.addObserver(
            self, selector: #selector(applied), name: .windowBarPreferencesApplied, object: nil)
        center.addObserver(
            self, selector: #selector(rejected), name: .windowBarPreferencesRejected, object: nil)
        controller.present()
    }

    @objc private func present() { settings?.present() }
    @objc private func applied() {
        features.preferences.reload()
        settings?.refresh()
    }
    @objc private func rejected() {
        features.preferences.reload()
        settings?.showExternalError(
            "The taskbar could not apply that change. The previous settings were restored; try another shortcut or setting."
        )
    }
}

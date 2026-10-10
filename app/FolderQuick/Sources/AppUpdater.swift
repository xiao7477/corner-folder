import AppKit
import Sparkle

final class AppUpdater: NSObject {
    static let shared = AppUpdater()

    private let controller = SPUStandardUpdaterController(
        startingUpdater: false,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )

    var updater: SPUUpdater { controller.updater }

    func start() {
        controller.startUpdater()
    }

    func makeMenuItem() -> NSMenuItem {
        let item = NSMenuItem(
            title: "检查更新…",
            action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)),
            keyEquivalent: ""
        )
        item.target = controller
        return item
    }

    @objc func checkForUpdates(_ sender: Any?) {
        guard updater.canCheckForUpdates else { return }
        AppLogger.info("User requested check for updates")
        controller.checkForUpdates(sender)
    }
}

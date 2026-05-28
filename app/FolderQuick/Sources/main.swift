import AppKit

final class FolderQuickApp: NSObject, NSApplicationDelegate {
    private var controller: SidebarWindowController?
    private var statusItem: NSStatusItem?
    private var hotkey: GlobalHotkey?
    private var statusMenu: NSMenu?

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller = SidebarWindowController()
        hotkey = GlobalHotkey { [weak self] in
            DispatchQueue.main.async {
                self?.controller?.toggleWindow()
            }
        }
        hotkey?.register()
        setupStatusItem()
        controller?.showWindow()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem?.button?.image = NSImage(systemSymbolName: "folder", accessibilityDescription: "FolderQuick")
        statusItem?.button?.target = self
        statusItem?.button?.action = #selector(statusItemClicked(_:))
        statusItem?.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "显示/隐藏 FolderQuick", action: #selector(toggleWindow), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "退出", action: #selector(quit), keyEquivalent: "q"))
        statusMenu = menu
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else {
            toggleWindow()
            return
        }

        if event.type == .rightMouseUp {
            guard let statusItem, let statusMenu else { return }
            statusItem.menu = statusMenu
            sender.performClick(nil)
            statusItem.menu = nil
        } else {
            toggleWindow()
        }
    }

    @objc private func toggleWindow() {
        controller?.toggleWindow()
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}

let app = NSApplication.shared
let delegate = FolderQuickApp()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()

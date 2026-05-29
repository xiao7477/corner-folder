import AppKit

final class FolderQuickApp: NSObject, NSApplicationDelegate {
    private var controller: SidebarWindowController?
    private var statusItem: NSStatusItem?
    private var hotkey: GlobalHotkey?
    private var statusMenu: NSMenu?
    private var statusTrackingArea: NSTrackingArea?
    private var statusHoverWorkItem: DispatchWorkItem?
    private var statusDragMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller = SidebarWindowController()
        hotkey = GlobalHotkey { [weak self] in
            DispatchQueue.main.async {
                self?.controller?.toggleWindow()
            }
        }
        hotkey?.register()
        setupStatusItem()
        installStatusDragMonitor()
        controller?.showWindow()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem?.button?.image = NSImage(systemSymbolName: "folder", accessibilityDescription: "FolderQuick")
        statusItem?.button?.target = self
        statusItem?.button?.action = #selector(statusItemClicked(_:))
        statusItem?.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        installStatusTrackingArea()

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

    func mouseEntered(with event: NSEvent) {
        scheduleStatusHoverOpen()
    }

    func mouseExited(with event: NSEvent) {
        cancelStatusHoverOpen()
    }

    @objc private func toggleWindow() {
        controller?.toggleWindow()
    }

    private func installStatusTrackingArea() {
        guard let button = statusItem?.button else { return }
        if let statusTrackingArea {
            button.removeTrackingArea(statusTrackingArea)
        }
        let trackingArea = NSTrackingArea(
            rect: button.bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        button.addTrackingArea(trackingArea)
        statusTrackingArea = trackingArea
    }

    private func installStatusDragMonitor() {
        statusDragMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged, .rightMouseDown]) { [weak self] event in
            DispatchQueue.main.async {
                if event.type == .rightMouseDown {
                    FolderQuickDragCancel.cancelCurrentDrag()
                    self?.cancelStatusHoverOpen()
                    return
                }
                guard let self,
                      let frame = self.statusButtonScreenFrame(),
                      frame.contains(NSEvent.mouseLocation) else {
                    self?.cancelStatusHoverOpen()
                    return
                }
                self.scheduleStatusHoverOpen()
            }
        }
    }

    private func statusButtonScreenFrame() -> NSRect? {
        guard let button = statusItem?.button,
              let window = button.window else {
            return nil
        }
        let rectInWindow = button.convert(button.bounds, to: nil)
        let origin = window.convertPoint(toScreen: rectInWindow.origin)
        return NSRect(origin: origin, size: rectInWindow.size).insetBy(dx: -8, dy: -8)
    }

    private func scheduleStatusHoverOpen() {
        guard statusHoverWorkItem == nil else { return }
        statusItem?.button?.contentTintColor = .controlAccentColor
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.controller?.showWindow()
            self.statusHoverWorkItem = nil
            self.statusItem?.button?.contentTintColor = nil
        }
        statusHoverWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: workItem)
    }

    private func cancelStatusHoverOpen() {
        statusHoverWorkItem?.cancel()
        statusHoverWorkItem = nil
        statusItem?.button?.contentTintColor = nil
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let statusDragMonitor {
            NSEvent.removeMonitor(statusDragMonitor)
        }
    }
}

let app = NSApplication.shared
let delegate = FolderQuickApp()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()

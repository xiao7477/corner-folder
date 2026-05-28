import AppKit
import Quartz

final class SidebarWindowController: NSObject {
    private let store = FolderStore.shared
    private let loader = FileLoader()
    private var settings: AppSettings
    private lazy var settingsPanel = SettingsPanel(settings: settings)

    private var panel: NSPanel!
    private var edgePanel: NSPanel!
    private var rootView = NSVisualEffectView()
    private var backButton = NSButton()
    private var rootButton = NSButton()
    private var refreshButton = NSButton()
    private var previewButton = NSButton()
    private var folderButton = NSPopUpButton()
    private var tabScrollView = NSScrollView()
    private var tabStack = NSStackView()
    private var addButton = NSButton()
    private var pinButton = NSButton()
    private var searchField = NSSearchField()
    private var typeButton = NSPopUpButton()
    private var timeButton = NSPopUpButton()
    private var collectionView = NSCollectionView()
    private var scrollView = NSScrollView()
    private var countLabel = NSTextField(labelWithString: "0 项")
    private var pathLabel = NSTextField(labelWithString: "未选择文件夹")
    private var settingsButton = NSButton()
    private var emptyLabel = NSTextField(labelWithString: "添加一个常用文件夹后开始使用")
    private var hideWorkItem: DispatchWorkItem?
    private var keyMonitor: Any?

    private var folders: [FolderEntry] = []
    private var selectedFolderID: UUID?
    private var selectedRootURL: URL?
    private var currentFolderURL: URL?
    private var navigationStack: [URL] = []
    private var allFiles: [FileEntry] = []
    private var shownFiles: [FileEntry] = []
    private var isPinned = false

    override init() {
        settings = store.loadSettings()
        super.init()
        folders = store.loadFolders()
        selectedFolderID = store.selectedFolderID() ?? folders.first?.id
        buildWindow()
        buildEdgeTrigger()
        buildInterface()
        settingsPanel.onSettingsChanged = { [weak self] settings in
            self?.applySettings(settings)
        }
        installKeyMonitor()
        reloadFolderMenu()
        loadSelectedFolder()
    }

    deinit {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
    }

    func showWindow() {
        positionPanel()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func toggleWindow() {
        if panel.isVisible {
            hideWindow()
        } else {
            showWindow()
        }
    }

    private func hideWindow() {
        panel.orderOut(nil)
    }

    private func buildWindow() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: settings.windowWidth, height: settings.windowHeight),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.title = "FolderQuick"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.alphaValue = settings.opacity
        panel.delegate = self
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
    }

    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool {
        true
    }

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = self
        panel.delegate = self
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = nil
        panel.delegate = nil
    }

    private func buildEdgeTrigger() {
        edgePanel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 8, height: 420),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        edgePanel.level = .floating
        edgePanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        edgePanel.backgroundColor = settings.showEdgeTrigger ? NSColor.controlAccentColor.withAlphaComponent(0.18) : .clear
        edgePanel.isOpaque = false
        edgePanel.hasShadow = false
        edgePanel.ignoresMouseEvents = false

        let triggerView = EdgeTriggerView()
        triggerView.wantsLayer = true
        triggerView.layer?.backgroundColor = NSColor.clear.cgColor
        triggerView.onMouseEnter = { [weak self] in
            self?.showWindow()
        }
        edgePanel.contentView = triggerView
        positionEdgeTrigger()
        edgePanel.orderFrontRegardless()
    }

    private func buildInterface() {
        rootView.material = .hudWindow
        rootView.blendingMode = .behindWindow
        rootView.state = .active
        rootView.wantsLayer = true
        rootView.layer?.cornerRadius = 18
        rootView.layer?.masksToBounds = true
        panel.contentView = rootView

        let mainStack = NSStackView()
        mainStack.orientation = .vertical
        mainStack.spacing = 0
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        rootView.addSubview(mainStack)

        NSLayoutConstraint.activate([
            mainStack.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            mainStack.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            mainStack.topAnchor.constraint(equalTo: rootView.topAnchor),
            mainStack.bottomAnchor.constraint(equalTo: rootView.bottomAnchor)
        ])

        mainStack.addArrangedSubview(makeTopBar())
        mainStack.addArrangedSubview(makeTabBar())
        mainStack.addArrangedSubview(makePathBar())
        mainStack.addArrangedSubview(makeFilterBar())
        mainStack.addArrangedSubview(makeContentView())
        mainStack.addArrangedSubview(makeBottomBar())
    }

    private func makeTopBar() -> NSView {
        let bar = NSView()
        bar.translatesAutoresizingMaskIntoConstraints = false
        bar.heightAnchor.constraint(equalToConstant: 78).isActive = true

        folderButton.font = .systemFont(ofSize: 18, weight: .semibold)
        folderButton.target = self
        folderButton.action = #selector(folderChanged)

        backButton = iconButton("chevron.left", action: #selector(goBack))
        rootButton = iconButton("house", action: #selector(goRoot))
        refreshButton = iconButton("arrow.clockwise", action: #selector(refreshFiles))
        previewButton = iconButton("eye", action: #selector(previewSelected))
        addButton = iconButton("folder.badge.plus", action: #selector(addFolder))
        pinButton = iconButton("pin", action: #selector(togglePin))

        let stack = NSStackView(views: [backButton, rootButton, refreshButton, previewButton, folderButton, addButton, pinButton])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 22),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: bar.trailingAnchor, constant: -22),
            stack.centerYAnchor.constraint(equalTo: bar.centerYAnchor)
        ])

        return bar
    }

    private func makePathBar() -> NSView {
        let bar = NSView()
        bar.translatesAutoresizingMaskIntoConstraints = false
        bar.heightAnchor.constraint(equalToConstant: 34).isActive = true

        pathLabel.font = .systemFont(ofSize: 12, weight: .medium)
        pathLabel.textColor = .secondaryLabelColor
        pathLabel.lineBreakMode = .byTruncatingMiddle
        pathLabel.maximumNumberOfLines = 1
        pathLabel.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(pathLabel)

        NSLayoutConstraint.activate([
            pathLabel.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 24),
            pathLabel.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -24),
            pathLabel.centerYAnchor.constraint(equalTo: bar.centerYAnchor)
        ])

        return bar
    }

    private func makeTabBar() -> NSView {
        let bar = NSView()
        bar.translatesAutoresizingMaskIntoConstraints = false
        bar.heightAnchor.constraint(equalToConstant: 46).isActive = true

        tabStack.orientation = .horizontal
        tabStack.alignment = .centerY
        tabStack.spacing = 8
        tabStack.edgeInsets = NSEdgeInsets(top: 6, left: 22, bottom: 6, right: 22)

        tabScrollView.documentView = tabStack
        tabScrollView.drawsBackground = false
        tabScrollView.hasHorizontalScroller = false
        tabScrollView.hasVerticalScroller = false
        tabScrollView.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(tabScrollView)

        NSLayoutConstraint.activate([
            tabScrollView.leadingAnchor.constraint(equalTo: bar.leadingAnchor),
            tabScrollView.trailingAnchor.constraint(equalTo: bar.trailingAnchor),
            tabScrollView.topAnchor.constraint(equalTo: bar.topAnchor),
            tabScrollView.bottomAnchor.constraint(equalTo: bar.bottomAnchor)
        ])

        return bar
    }

    private func makeFilterBar() -> NSView {
        let bar = NSView()
        bar.translatesAutoresizingMaskIntoConstraints = false
        bar.heightAnchor.constraint(equalToConstant: 62).isActive = true

        searchField.placeholderString = "搜索文件"
        searchField.target = self
        searchField.action = #selector(applyFilters)
        searchField.sendsSearchStringImmediately = true
        searchField.delegate = self
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.widthAnchor.constraint(equalToConstant: 210).isActive = true

        timeButton.addItems(withTitles: ["全部时间", "今天", "昨天", "最近 7 天", "最近 30 天"])
        timeButton.target = self
        timeButton.action = #selector(applyFilters)

        typeButton.addItems(withTitles: FileKind.allCases.map(\.rawValue))
        typeButton.target = self
        typeButton.action = #selector(applyFilters)

        let stack = NSStackView(views: [searchField, timeButton, typeButton])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 22),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: bar.trailingAnchor, constant: -22),
            stack.centerYAnchor.constraint(equalTo: bar.centerYAnchor)
        ])

        return bar
    }

    private func makeContentView() -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let layout = NSCollectionViewFlowLayout()
        layout.itemSize = itemSize()
        layout.sectionInset = NSEdgeInsets(top: 24, left: 34, bottom: 24, right: 34)
        layout.minimumInteritemSpacing = 26
        layout.minimumLineSpacing = 38

        collectionView.collectionViewLayout = layout
        collectionView.register(FileItemView.self, forItemWithIdentifier: FileItemView.identifier)
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.isSelectable = true
        collectionView.allowsMultipleSelection = true
        collectionView.backgroundColors = [.clear]
        collectionView.setDraggingSourceOperationMask(.copy, forLocal: false)

        scrollView.documentView = collectionView
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        emptyLabel.font = .systemFont(ofSize: 16, weight: .medium)
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.alignment = .center
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(scrollView)
        container.addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: container.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            emptyLabel.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])

        return container
    }

    private func makeBottomBar() -> NSView {
        let bar = NSView()
        bar.translatesAutoresizingMaskIntoConstraints = false
        bar.heightAnchor.constraint(equalToConstant: 72).isActive = true

        countLabel.font = .systemFont(ofSize: 14, weight: .medium)
        countLabel.textColor = .secondaryLabelColor

        settingsButton = iconButton("gearshape", action: #selector(openSettings))

        let stack = NSStackView(views: [countLabel, settingsButton])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.distribution = .equalSpacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -24),
            stack.centerYAnchor.constraint(equalTo: bar.centerYAnchor)
        ])

        return bar
    }

    private func iconButton(_ systemName: String, action: Selector) -> NSButton {
        let button = NSButton()
        button.image = NSImage(systemSymbolName: systemName, accessibilityDescription: nil)
        button.bezelStyle = .texturedRounded
        button.isBordered = false
        button.target = self
        button.action = action
        button.widthAnchor.constraint(equalToConstant: 36).isActive = true
        button.heightAnchor.constraint(equalToConstant: 32).isActive = true
        return button
    }

    private func positionPanel() {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let width = min(panel.frame.width, visible.width * 0.72)
        let height = min(panel.frame.height, visible.height * 0.86)
        let x: Double
        switch settings.sidebarPosition {
        case .right:
            x = visible.maxX - width - 18
        case .left:
            x = visible.minX + 18
        }
        let y = visible.midY - height / 2
        panel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
        positionEdgeTrigger()
    }

    private func positionEdgeTrigger() {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let x: Double
        switch settings.sidebarPosition {
        case .right:
            x = visible.maxX - 2
        case .left:
            x = visible.minX - 6
        }
        edgePanel?.setFrame(
            NSRect(x: x, y: visible.midY - 210, width: 8, height: 420),
            display: true
        )
    }

    private func reloadFolderMenu() {
        folderButton.removeAllItems()

        if folders.isEmpty {
            folderButton.addItem(withTitle: "添加文件夹")
        } else {
            for folder in folders {
                folderButton.addItem(withTitle: folder.name)
                folderButton.lastItem?.representedObject = folder.id.uuidString
            }
            if let selectedFolderID,
               let index = folders.firstIndex(where: { $0.id == selectedFolderID }) {
                folderButton.selectItem(at: index)
            }
        }

        reloadTabs()
    }

    private func reloadTabs() {
        tabStack.arrangedSubviews.forEach { view in
            tabStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        if folders.isEmpty {
            let hint = NSTextField(labelWithString: "还没有标签，先添加一个常用文件夹")
            hint.font = .systemFont(ofSize: 13, weight: .medium)
            hint.textColor = .secondaryLabelColor
            tabStack.addArrangedSubview(hint)
            return
        }

        for (index, folder) in folders.enumerated() {
            let button = NSButton(title: folder.name, target: self, action: #selector(tabClicked(_:)))
            button.tag = index
            button.bezelStyle = folder.id == selectedFolderID ? .rounded : .texturedRounded
            button.isBordered = true
            button.font = .systemFont(ofSize: 13, weight: folder.id == selectedFolderID ? .semibold : .regular)
            button.contentTintColor = folder.id == selectedFolderID ? .controlAccentColor : nil
            button.setButtonType(.momentaryPushIn)
            tabStack.addArrangedSubview(button)
        }
    }

    private func loadSelectedFolder() {
        guard let selectedFolderID,
              let folder = folders.first(where: { $0.id == selectedFolderID }),
              let url = store.resolve(folder) else {
            selectedRootURL = nil
            currentFolderURL = nil
            allFiles = []
            shownFiles = []
            pathLabel.stringValue = folders.isEmpty ? "未选择文件夹" : "文件夹权限失效，请重新添加"
            refreshCollection()
            return
        }

        selectedRootURL = url
        currentFolderURL = url
        navigationStack = []
        reloadFiles(from: url)
        reloadTabs()
        applyFilters()
    }

    private func refreshCollection() {
        emptyLabel.isHidden = !shownFiles.isEmpty || (!folders.isEmpty && !allFiles.isEmpty)
        if folders.isEmpty {
            emptyLabel.stringValue = "添加一个常用文件夹后开始使用"
        } else if allFiles.isEmpty {
            emptyLabel.stringValue = "这个文件夹是空的，或暂时没有读取权限"
        } else if shownFiles.isEmpty {
            emptyLabel.stringValue = "没有找到匹配的文件"
        }
        countLabel.stringValue = "\(shownFiles.count) 项"
        backButton.isEnabled = !navigationStack.isEmpty
        rootButton.isEnabled = currentFolderURL != nil && currentFolderURL != selectedRootURL
        refreshButton.isEnabled = currentFolderURL != nil
        previewButton.isEnabled = selectedPreviewURL() != nil
        updatePathLabel()
        collectionView.reloadData()
    }

    private func reloadFiles(from url: URL) {
        allFiles = loader.loadFiles(in: url)
    }

    private func updatePathLabel() {
        guard let currentFolderURL else {
            pathLabel.stringValue = "未选择文件夹"
            return
        }

        if let selectedRootURL, currentFolderURL == selectedRootURL {
            pathLabel.stringValue = currentFolderURL.lastPathComponent
        } else {
            pathLabel.stringValue = currentFolderURL.path
        }
    }

    private func itemSize() -> NSSize {
        let width = settings.iconSize
        return NSSize(width: width, height: width + 8)
    }

    private func applyItemSize() {
        guard let layout = collectionView.collectionViewLayout as? NSCollectionViewFlowLayout else { return }
        layout.itemSize = itemSize()
        layout.invalidateLayout()
    }

    @objc private func addFolder() {
        let openPanel = NSOpenPanel()
        openPanel.title = "选择常用文件夹"
        openPanel.canChooseFiles = false
        openPanel.canChooseDirectories = true
        openPanel.allowsMultipleSelection = false

        guard openPanel.runModal() == .OK, let url = openPanel.url else { return }

        do {
            let bookmark = try store.bookmark(for: url)
            let entry = FolderEntry(id: UUID(), name: url.lastPathComponent, bookmarkData: bookmark)
            folders.append(entry)
            selectedFolderID = entry.id
            store.saveFolders(folders)
            store.saveSelectedFolderID(entry.id)
            reloadFolderMenu()
            loadSelectedFolder()
        } catch {
            showAlert(title: "无法添加文件夹", message: "系统没有允许保存这个文件夹的访问权限。")
        }
    }

    @objc private func folderChanged() {
        guard let text = folderButton.selectedItem?.representedObject as? String,
              let id = UUID(uuidString: text) else {
            addFolder()
            return
        }
        selectedFolderID = id
        store.saveSelectedFolderID(id)
        loadSelectedFolder()
    }

    @objc private func tabClicked(_ sender: NSButton) {
        guard folders.indices.contains(sender.tag) else { return }
        let id = folders[sender.tag].id
        selectedFolderID = id
        store.saveSelectedFolderID(id)
        if let index = folders.firstIndex(where: { $0.id == id }) {
            folderButton.selectItem(at: index)
        }
        loadSelectedFolder()
    }

    @objc private func togglePin() {
        isPinned.toggle()
        pinButton.contentTintColor = isPinned ? .controlAccentColor : nil
    }

    @objc private func goBack() {
        guard let previous = navigationStack.popLast() else { return }
        currentFolderURL = previous
        reloadFiles(from: previous)
        applyFilters()
    }

    @objc private func goRoot() {
        guard let selectedRootURL else { return }
        currentFolderURL = selectedRootURL
        navigationStack = []
        reloadFiles(from: selectedRootURL)
        applyFilters()
    }

    @objc private func refreshFiles() {
        guard let currentFolderURL else { return }
        reloadFiles(from: currentFolderURL)
        applyFilters()
    }

    @objc private func openSettings() {
        settingsPanel.update(settings: settings)
        settingsPanel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func applyFilters() {
        let keyword = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let selectedKind = FileKind.allCases.first { $0.rawValue == typeButton.titleOfSelectedItem } ?? .all
        let selectedTime = timeButton.titleOfSelectedItem ?? "全部时间"

        shownFiles = allFiles.filter { entry in
            let matchesKeyword = keyword.isEmpty || entry.name.localizedCaseInsensitiveContains(keyword)
            let matchesKind = selectedKind == .all || entry.kind == selectedKind
            let matchesTime = matchesTimeFilter(entry.modifiedAt, title: selectedTime)
            return matchesKeyword && matchesKind && matchesTime
        }

        refreshCollection()
    }

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.panel.isVisible else { return event }
            if event.keyCode == 49 {
                self.previewSelected()
                return nil
            }
            if event.keyCode == 53 {
                self.hideWindow()
                return nil
            }
            return event
        }
    }

    private func selectedPreviewURL() -> URL? {
        guard let indexPath = collectionView.selectionIndexPaths.first else { return nil }
        guard shownFiles.indices.contains(indexPath.item) else { return nil }
        let entry = shownFiles[indexPath.item]
        return entry.isDirectory ? nil : entry.url
    }

    @objc private func previewSelected() {
        guard selectedPreviewURL() != nil else { return }
        if let panel = QLPreviewPanel.shared() {
            panel.dataSource = self
            panel.delegate = self
            panel.reloadData()
            panel.makeKeyAndOrderFront(nil)
        }
    }

    private func applySettings(_ newSettings: AppSettings) {
        settings = newSettings
        store.saveSettings(settings)
        panel.alphaValue = settings.opacity
        edgePanel.backgroundColor = settings.showEdgeTrigger ? NSColor.controlAccentColor.withAlphaComponent(0.18) : .clear
        applyItemSize()
        positionPanel()
    }

    private func matchesTimeFilter(_ date: Date?, title: String) -> Bool {
        guard title != "全部时间" else { return true }
        guard let date else { return false }

        let calendar = Calendar.current
        let now = Date()

        switch title {
        case "今天":
            return calendar.isDateInToday(date)
        case "昨天":
            return calendar.isDateInYesterday(date)
        case "最近 7 天":
            return date >= calendar.date(byAdding: .day, value: -7, to: now) ?? now
        case "最近 30 天":
            return date >= calendar.date(byAdding: .day, value: -30, to: now) ?? now
        default:
            return true
        }
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }
}

extension SidebarWindowController: NSWindowDelegate {
    func windowDidResignKey(_ notification: Notification) {
        if !isPinned {
            hideWorkItem?.cancel()
            let workItem = DispatchWorkItem { [weak self] in
                self?.hideWindow()
            }
            hideWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + settings.autoHideDelay, execute: workItem)
        }
    }

    func windowDidResize(_ notification: Notification) {
        guard notification.object as AnyObject? === panel else { return }
        settings.windowWidth = panel.frame.width
        settings.windowHeight = panel.frame.height
        store.saveSettings(settings)
    }
}

extension SidebarWindowController: NSCollectionViewDataSource, NSCollectionViewDelegate {
    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        shownFiles.count
    }

    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let item = collectionView.makeItem(withIdentifier: FileItemView.identifier, for: indexPath)
        if let fileItem = item as? FileItemView {
            fileItem.configure(with: shownFiles[indexPath.item], iconSize: settings.iconSize)
        }
        return item
    }

    func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
        previewButton.isEnabled = selectedPreviewURL() != nil
        guard let event = NSApp.currentEvent, event.clickCount == 2, let indexPath = indexPaths.first else { return }
        let entry = shownFiles[indexPath.item]
        if entry.isDirectory {
            if let currentFolderURL {
                navigationStack.append(currentFolderURL)
            }
            currentFolderURL = entry.url
            reloadFiles(from: entry.url)
            applyFilters()
        } else {
            NSWorkspace.shared.open(entry.url)
        }
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        pasteboardWriterForItemAt indexPath: IndexPath
    ) -> NSPasteboardWriting? {
        shownFiles[indexPath.item].url as NSURL
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        menuForItemsAt indexPaths: Set<IndexPath>,
        point: NSPoint
    ) -> NSMenu? {
        guard let indexPath = indexPaths.first else { return nil }
        let entry = shownFiles[indexPath.item]
        let menu = NSMenu()
        let open = NSMenuItem(title: "打开", action: #selector(openMenuItem(_:)), keyEquivalent: "")
        open.representedObject = entry.url
        open.target = self
        menu.addItem(open)

        let reveal = NSMenuItem(title: "在 Finder 中显示", action: #selector(revealMenuItem(_:)), keyEquivalent: "")
        reveal.representedObject = entry.url
        reveal.target = self
        menu.addItem(reveal)
        return menu
    }

    @objc private func openMenuItem(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func revealMenuItem(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}

extension SidebarWindowController: QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        selectedPreviewURL() == nil ? 0 : 1
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        selectedPreviewURL() as NSURL?
    }

}

extension SidebarWindowController: NSSearchFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        applyFilters()
    }
}

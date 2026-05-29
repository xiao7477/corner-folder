import AppKit
import Quartz

final class SidebarWindowController: NSObject {
    private let store = FolderStore.shared
    private let loader = FileLoader()
    private var settings: AppSettings
    private lazy var settingsPanel = SettingsPanel(settings: settings)

    private var panel: NSPanel!
    private var edgePanels: [NSPanel] = []
    private var rootView = NSVisualEffectView()
    private var backButton = NSButton()
    private var rootButton = NSButton()
    private var refreshButton = NSButton()
    private var previewButton = NSButton()
    private var folderButton = NSPopUpButton()
    private var tabScrollView = HorizontalTabScrollView()
    private var tabBarView = TabBarView()
    private var addButton = NSButton()
    private var pinButton = NSButton()
    private var searchField = NSSearchField()
    private var typeButton = NSPopUpButton()
    private var timeButton = NSPopUpButton()
    private var viewModeControl = NSSegmentedControl(labels: FileViewMode.allCases.map(\.rawValue), trackingMode: .selectOne, target: nil, action: nil)
    private var collectionView = FileCollectionView()
    private var scrollView = FileDropScrollView()
    private var outlineView = FileOutlineView()
    private var listScrollView = FileDropScrollView()
    private var countLabel = NSTextField(labelWithString: "0 项")
    private var pathLabel = NSTextField(labelWithString: "未选择文件夹")
    private var levelDotsStack = NSStackView()
    private var settingsButton = NSButton()
    private var emptyLabel = NSTextField(labelWithString: "添加一个常用文件夹后开始使用")
    private var hideWorkItem: DispatchWorkItem?
    private var hoverFolderWorkItem: DispatchWorkItem?
    private var hoveredDropFolderURL: URL?
    private var keyMonitor: Any?
    private var mouseMonitor: Any?

    private var folders: [FolderEntry] = []
    private var selectedFolderID: UUID?
    private var selectedRootURL: URL?
    private var currentFolderURL: URL?
    private var navigationStack: [URL] = []
    private var allFiles: [FileEntry] = []
    private var shownFiles: [FileEntry] = []
    private var listRootNodes: [FileNode] = []
    private var folderNavigationStates: [UUID: FolderNavigationState] = [:]
    private var isPinned = false
    private var isTabMoveMode = false

    private struct FolderNavigationState {
        var rootURL: URL
        var currentURL: URL
        var stack: [URL]
        var expandedListPaths: Set<String>
    }

    override init() {
        settings = store.loadSettings()
        super.init()
        folders = store.loadFolders()
        selectedFolderID = store.selectedFolderID() ?? folders.first?.id
        buildWindow()
        rebuildEdgeTriggers()
        buildInterface()
        settingsPanel.onSettingsChanged = { [weak self] settings in
            self?.applySettings(settings)
        }
        installKeyMonitor()
        installMouseMonitor()
        reloadFolderMenu()
        loadSelectedFolder()
    }

    deinit {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        if let mouseMonitor {
            NSEvent.removeMonitor(mouseMonitor)
        }
    }

    func showWindow() {
        positionPanel(anchor: settings.sidebarPosition, screen: screenContainingMouse() ?? NSScreen.main)
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func showWindow(anchor: WindowAnchor, screen: NSScreen) {
        positionPanel(anchor: anchor, screen: screen)
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

    private func makeEdgeTrigger(anchor: WindowAnchor, screen: NSScreen) -> NSPanel {
        let edgePanel = NSPanel(
            contentRect: edgeFrame(anchor: anchor, screen: screen),
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
            self?.showWindow(anchor: anchor, screen: screen)
        }
        edgePanel.contentView = triggerView
        return edgePanel
    }

    private func rebuildEdgeTriggers() {
        edgePanels.forEach { $0.orderOut(nil) }
        edgePanels = []

        guard settings.edgeTriggerEnabled else { return }
        for screen in NSScreen.screens {
            for anchor in settings.triggerPositions {
                let trigger = makeEdgeTrigger(anchor: anchor, screen: screen)
                edgePanels.append(trigger)
                trigger.orderFrontRegardless()
            }
        }
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
        mainStack.addArrangedSubview(makeFilterBar())
        mainStack.addArrangedSubview(makeContentView())
        mainStack.addArrangedSubview(makeBottomBar())
    }

    private func makeTopBar() -> NSView {
        let bar = NSView()
        bar.translatesAutoresizingMaskIntoConstraints = false
        bar.heightAnchor.constraint(equalToConstant: 44).isActive = true

        tabBarView.onDropTab = { [weak self] from, to in
            self?.moveFolderTab(from: from, to: to)
        }

        backButton = iconButton("chevron.left", action: #selector(goBack))
        refreshButton = iconButton("arrow.clockwise", action: #selector(refreshFiles))
        addButton = iconButton("folder.badge.plus", action: #selector(addFolder))
        pinButton = iconButton("pin", action: #selector(togglePin))

        tabScrollView.documentView = tabBarView
        tabScrollView.drawsBackground = false
        tabScrollView.hasHorizontalScroller = false
        tabScrollView.hasVerticalScroller = false
        tabScrollView.borderType = .noBorder
        tabScrollView.automaticallyAdjustsContentInsets = false
        tabScrollView.contentView.postsBoundsChangedNotifications = true
        tabScrollView.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [tabScrollView, addButton, pinButton])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -12),
            stack.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            tabScrollView.heightAnchor.constraint(equalToConstant: 36)
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

    private func makeFilterBar() -> NSView {
        let bar = NSView()
        bar.translatesAutoresizingMaskIntoConstraints = false
        bar.heightAnchor.constraint(equalToConstant: 50).isActive = true

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

        backButton = iconButton("chevron.left", action: #selector(goBack))
        viewModeControl.selectedSegment = FileViewMode.allCases.firstIndex(of: settings.viewMode) ?? 0
        viewModeControl.target = self
        viewModeControl.action = #selector(viewModeChanged)

        let stack = NSStackView(views: [backButton, searchField, timeButton, typeButton, viewModeControl])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: bar.trailingAnchor, constant: -12),
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
        layout.minimumInteritemSpacing = settings.iconSpacing
        layout.minimumLineSpacing = settings.iconSpacing + 10

        collectionView.collectionViewLayout = layout
        collectionView.register(FileItemView.self, forItemWithIdentifier: FileItemView.identifier)
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.isSelectable = true
        collectionView.allowsMultipleSelection = true
        collectionView.backgroundColors = [.clear]
        collectionView.setDraggingSourceOperationMask(.copy, forLocal: false)
        collectionView.menuProvider = { [weak self] in
            self?.primarySelectedEntry() == nil ? nil : self?.fileMenu()
        }
        collectionView.onDoubleClickItem = { [weak self] indexPath in
            self?.openGridItem(at: indexPath)
        }
        collectionView.onDropFiles = { [weak self] urls, indexPath in
            guard let self else { return false }
            return self.importFiles(urls, to: self.dropDestinationForGrid(indexPath: indexPath))
        }
        collectionView.onHoverItem = { [weak self] indexPath in
            self?.handleGridDropHover(indexPath: indexPath)
        }
        scrollView.onDropFiles = { [weak self] urls in
            self?.importFiles(urls) ?? false
        }

        scrollView.documentView = collectionView
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        column.title = "名称"
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column
        outlineView.headerView = nil
        outlineView.rowHeight = 30
        outlineView.backgroundColor = .clear
        outlineView.delegate = self
        outlineView.dataSource = self
        outlineView.target = self
        outlineView.doubleAction = #selector(outlineDoubleClicked)
        outlineView.menuProvider = { [weak self] in
            self?.fileMenu()
        }
        outlineView.onDropFiles = { [weak self] urls, row in
            guard let self else { return false }
            return self.importFiles(urls, to: self.dropDestinationForList(row: row))
        }
        outlineView.onHoverRow = { [weak self] row in
            self?.handleListDropHover(row: row)
        }
        outlineView.setDraggingSourceOperationMask(.copy, forLocal: false)
        outlineView.setDraggingSourceOperationMask(.copy, forLocal: true)
        listScrollView.onDropFiles = { [weak self] urls in
            self?.importFiles(urls) ?? false
        }
        outlineView.usesAlternatingRowBackgroundColors = false
        outlineView.allowsMultipleSelection = true
        listScrollView.documentView = outlineView
        listScrollView.drawsBackground = false
        listScrollView.hasVerticalScroller = true
        listScrollView.translatesAutoresizingMaskIntoConstraints = false

        emptyLabel.font = .systemFont(ofSize: 16, weight: .medium)
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.alignment = .center
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(scrollView)
        container.addSubview(listScrollView)
        container.addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: container.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            listScrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            listScrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            listScrollView.topAnchor.constraint(equalTo: container.topAnchor),
            listScrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            emptyLabel.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])

        updateContentMode()

        return container
    }

    private func makeBottomBar() -> NSView {
        let bar = NSView()
        bar.translatesAutoresizingMaskIntoConstraints = false
        bar.heightAnchor.constraint(equalToConstant: 44).isActive = true

        countLabel.font = .systemFont(ofSize: 14, weight: .medium)
        countLabel.textColor = .secondaryLabelColor

        pathLabel.font = .systemFont(ofSize: 12)
        pathLabel.textColor = .secondaryLabelColor
        pathLabel.lineBreakMode = .byTruncatingMiddle
        pathLabel.maximumNumberOfLines = 1
        pathLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        pathLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

        levelDotsStack.orientation = .horizontal
        levelDotsStack.alignment = .centerY
        levelDotsStack.spacing = 6
        levelDotsStack.translatesAutoresizingMaskIntoConstraints = false

        settingsButton = iconButton("gearshape", action: #selector(openSettings))
        refreshButton = iconButton("arrow.clockwise", action: #selector(refreshFiles))

        let stack = NSStackView(views: [levelDotsStack, countLabel, pathLabel, refreshButton, settingsButton])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.distribution = .fill
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -14),
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

    private func screenContainingMouse() -> NSScreen? {
        let point = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) }
    }

    private func positionPanel(anchor: WindowAnchor, screen: NSScreen?) {
        guard let screen else { return }
        let visible = screen.visibleFrame
        let width = min(panel.frame.width, visible.width * 0.72)
        let height = min(panel.frame.height, visible.height * 0.86)
        let margin = 14.0

        let x: Double = {
            switch anchor {
            case .left, .topLeft, .bottomLeft:
                return visible.minX + margin
            case .right, .topRight, .bottomRight:
                return visible.maxX - width - margin
            case .top, .bottom:
                return visible.midX - width / 2
            }
        }()

        let y: Double = {
            switch anchor {
            case .top, .topLeft, .topRight:
                return visible.maxY - height - margin
            case .bottom, .bottomLeft, .bottomRight:
                return visible.minY + margin
            case .left, .right:
                return visible.midY - height / 2
            }
        }()

        panel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
    }

    private func edgeFrame(anchor: WindowAnchor, screen: NSScreen) -> NSRect {
        let frame = screen.frame
        let length = 420.0
        let thickness = 8.0
        let corner = 72.0
        switch anchor {
        case .left:
            return NSRect(x: frame.minX, y: frame.midY - length / 2, width: thickness, height: length)
        case .right:
            return NSRect(x: frame.maxX - thickness, y: frame.midY - length / 2, width: thickness, height: length)
        case .top:
            return NSRect(x: frame.midX - length / 2, y: frame.maxY - thickness, width: length, height: thickness)
        case .bottom:
            return NSRect(x: frame.midX - length / 2, y: frame.minY, width: length, height: thickness)
        case .topLeft:
            return NSRect(x: frame.minX, y: frame.maxY - corner, width: corner, height: corner)
        case .topRight:
            return NSRect(x: frame.maxX - corner, y: frame.maxY - corner, width: corner, height: corner)
        case .bottomLeft:
            return NSRect(x: frame.minX, y: frame.minY, width: corner, height: corner)
        case .bottomRight:
            return NSRect(x: frame.maxX - corner, y: frame.minY, width: corner, height: corner)
        }
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
        tabBarView.subviews.forEach { view in
            view.removeFromSuperview()
        }

        if folders.isEmpty {
            let hint = NSTextField(labelWithString: "还没有标签，先添加一个常用文件夹")
            hint.font = .systemFont(ofSize: 13, weight: .medium)
            hint.textColor = .secondaryLabelColor
            hint.frame = NSRect(x: 8, y: 7, width: 220, height: 20)
            tabBarView.addSubview(hint)
            tabBarView.frame = NSRect(x: 0, y: 0, width: 240, height: 36)
            return
        }

        var x = 0.0
        for (index, folder) in folders.enumerated() {
            let button = FolderTabButton()
            button.title = folder.name
            button.folderIndex = index
            button.isSelected = folder.id == selectedFolderID
            button.isMoveModeEnabled = isTabMoveMode
            button.onClick = { [weak self] index in
                self?.selectFolderTab(index: index)
            }
            button.menuProvider = { [weak self] index in
                self?.folderMenu(index: index)
            }
            let width = min(190, max(84, folder.name.size(withAttributes: [.font: NSFont.systemFont(ofSize: 13, weight: .medium)]).width + 34))
            button.frame = NSRect(x: x, y: 1, width: width, height: 32)
            tabBarView.addSubview(button)
            x += width + 6
        }
        tabBarView.frame = NSRect(x: 0, y: 0, width: max(x, tabScrollView.contentSize.width), height: 34)
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
        let state = folderNavigationStates[selectedFolderID]
        if let state, state.rootURL == url, FileManager.default.fileExists(atPath: state.currentURL.path) {
            currentFolderURL = state.currentURL
            navigationStack = state.stack.filter { FileManager.default.fileExists(atPath: $0.path) }
        } else {
            currentFolderURL = url
            navigationStack = []
            saveCurrentFolderState()
        }
        reloadFiles(from: currentFolderURL ?? url)
        reloadTabs()
        applyFilters()
    }

    private func saveCurrentFolderState() {
        guard let selectedFolderID, let selectedRootURL, let currentFolderURL else { return }
        folderNavigationStates[selectedFolderID] = FolderNavigationState(
            rootURL: selectedRootURL,
            currentURL: currentFolderURL,
            stack: navigationStack,
            expandedListPaths: folderNavigationStates[selectedFolderID]?.expandedListPaths ?? []
        )
    }

    private func resetFolderStateToRoot(id: UUID) {
        guard let folder = folders.first(where: { $0.id == id }),
              let rootURL = store.resolve(folder) else { return }
        folderNavigationStates[id] = FolderNavigationState(rootURL: rootURL, currentURL: rootURL, stack: [], expandedListPaths: [])

        guard selectedFolderID == id else { return }
        selectedRootURL = rootURL
        currentFolderURL = rootURL
        navigationStack = []
        reloadFiles(from: rootURL)
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
        refreshButton.isEnabled = currentFolderURL != nil
        previewButton.isEnabled = selectedPreviewURL() != nil
        updatePathLabel()
        updateLevelDots()
        rebuildListNodes()
        collectionView.reloadData()
        outlineView.reloadData()
        restoreExpandedListState()
    }

    private func reloadFiles(from url: URL) {
        allFiles = loader.loadFiles(in: url)
    }

    private func updatePathLabel() {
        guard let currentFolderURL else {
            pathLabel.stringValue = "未选择文件夹"
            pathLabel.toolTip = nil
            pathLabel.isHidden = !settings.showBottomPath
            return
        }

        if let selectedRootURL, currentFolderURL == selectedRootURL {
            pathLabel.stringValue = currentFolderURL.lastPathComponent
        } else {
            pathLabel.stringValue = currentFolderURL.path
        }
        pathLabel.toolTip = currentFolderURL.path
        pathLabel.isHidden = !settings.showBottomPath
    }

    private func itemSize() -> NSSize {
        let width = settings.iconSize
        return NSSize(width: width, height: width + (width < 76 ? 22 : 28))
    }

    private func applyItemSize() {
        guard let layout = collectionView.collectionViewLayout as? NSCollectionViewFlowLayout else { return }
        layout.itemSize = itemSize()
        layout.minimumInteritemSpacing = settings.iconSpacing
        layout.minimumLineSpacing = settings.iconSpacing + 10
        layout.invalidateLayout()
    }

    private func updateContentMode() {
        let showList = settings.viewMode == .list
        scrollView.isHidden = showList
        listScrollView.isHidden = !showList
        viewModeControl.selectedSegment = FileViewMode.allCases.firstIndex(of: settings.viewMode) ?? 0
        updateLevelDots()
    }

    private func navigationPathURLs() -> [URL] {
        guard let currentFolderURL else { return [] }
        var urls = navigationStack
        urls.append(currentFolderURL)
        return urls
    }

    private func updateLevelDots() {
        levelDotsStack.arrangedSubviews.forEach { view in
            levelDotsStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        let urls = levelDotURLs()
        guard urls.count > 1 else {
            levelDotsStack.isHidden = true
            return
        }

        levelDotsStack.isHidden = false
        for (index, url) in urls.enumerated() {
            let dot = NSButton()
            dot.title = ""
            dot.bezelStyle = .regularSquare
            dot.isBordered = false
            dot.wantsLayer = true
            dot.layer?.cornerRadius = index == urls.count - 1 ? 4.5 : 3.5
            dot.layer?.backgroundColor = index == urls.count - 1
                ? NSColor.controlAccentColor.cgColor
                : NSColor.secondaryLabelColor.withAlphaComponent(0.45).cgColor
            dot.toolTip = url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent
            dot.tag = index
            dot.target = self
            dot.action = #selector(goToNavigationLevel(_:))
            dot.translatesAutoresizingMaskIntoConstraints = false
            dot.widthAnchor.constraint(equalToConstant: index == urls.count - 1 ? 9 : 7).isActive = true
            dot.heightAnchor.constraint(equalToConstant: index == urls.count - 1 ? 9 : 7).isActive = true
            levelDotsStack.addArrangedSubview(dot)
        }
    }

    private func rebuildListNodes() {
        listRootNodes = shownFiles.map { FileNode(entry: $0) }
    }

    private func restoreExpandedListState() {
        guard settings.viewMode == .list,
              let selectedFolderID,
              let expandedPaths = folderNavigationStates[selectedFolderID]?.expandedListPaths,
              !expandedPaths.isEmpty else {
            return
        }

        let orderedPaths = expandedPaths.sorted { left, right in
            left.split(separator: "/").count < right.split(separator: "/").count
        }
        for path in orderedPaths {
            _ = expandListNode(path: path, in: listRootNodes)
        }
    }

    private func expandListNode(path: String, in nodes: [FileNode]) -> Bool {
        for node in nodes {
            guard node.entry.url.path != path else {
                outlineView.expandItem(node)
                return true
            }

            guard path.hasPrefix(node.entry.url.path + "/") else { continue }
            outlineView.expandItem(node)
            if expandListNode(path: path, in: loadChildren(for: node)) {
                return true
            }
        }
        return false
    }

    private func setListNode(_ node: FileNode, expanded: Bool) {
        guard let selectedFolderID else { return }
        var state = folderNavigationStates[selectedFolderID]
        if state == nil, let selectedRootURL, let currentFolderURL {
            state = FolderNavigationState(rootURL: selectedRootURL, currentURL: currentFolderURL, stack: navigationStack, expandedListPaths: [])
        }
        guard var nextState = state else { return }

        if expanded {
            nextState.expandedListPaths.insert(node.entry.url.path)
        } else {
            nextState.expandedListPaths = nextState.expandedListPaths.filter { path in
                path != node.entry.url.path && !path.hasPrefix(node.entry.url.path + "/")
            }
        }
        folderNavigationStates[selectedFolderID] = nextState
    }

    private func loadChildren(for node: FileNode) -> [FileNode] {
        if let children = node.children {
            return children
        }
        guard node.entry.isDirectory else {
            node.children = []
            return []
        }
        let children = loader.loadFiles(in: node.entry.url).map { FileNode(entry: $0, parent: node) }
        node.children = children
        return children
    }

    private func levelDotURLs() -> [URL] {
        navigationPathURLs()
    }

    private func selectedEntries() -> [FileEntry] {
        if settings.viewMode == .list {
            return outlineView.selectedRowIndexes.compactMap { row in
                guard row >= 0, let node = outlineView.item(atRow: row) as? FileNode else { return nil }
                return node.entry
            }
        }
        return collectionView.selectionIndexPaths.compactMap { indexPath in
            shownFiles.indices.contains(indexPath.item) ? shownFiles[indexPath.item] : nil
        }
    }

    private func primarySelectedEntry() -> FileEntry? {
        selectedEntries().first
    }

    private func folderMenu(index: Int) -> NSMenu {
        let menu = NSMenu()
        let reveal = NSMenuItem(title: "在访达中打开", action: #selector(revealFolderTab(_:)), keyEquivalent: "")
        reveal.tag = index
        reveal.target = self
        menu.addItem(reveal)

        let home = NSMenuItem(title: "回到首页", action: #selector(resetFolderTabToRoot(_:)), keyEquivalent: "")
        home.tag = index
        home.target = self
        menu.addItem(home)

        let move = NSMenuItem(title: isTabMoveMode ? "完成移动" : "移动", action: #selector(toggleFolderTabMoveMode(_:)), keyEquivalent: "")
        move.tag = index
        move.target = self
        menu.addItem(move)

        let remove = NSMenuItem(title: "删除标签", action: #selector(deleteFolderTab(_:)), keyEquivalent: "")
        remove.tag = index
        remove.target = self
        menu.addItem(remove)
        return menu
    }

    private func moveFolderTab(from: Int, to: Int) {
        guard folders.indices.contains(from), (0...folders.count).contains(to) else { return }
        var target = to
        let folder = folders.remove(at: from)
        if target > from {
            target -= 1
        }
        target = min(max(0, target), folders.count)
        guard target != from else {
            folders.insert(folder, at: from)
            return
        }
        folders.insert(folder, at: target)
        store.saveFolders(folders)
        reloadFolderMenu()
    }

    @objc private func toggleFolderTabMoveMode(_ sender: NSMenuItem) {
        isTabMoveMode.toggle()
        reloadTabs()
    }

    private func setTabMoveMode(_ isEnabled: Bool) {
        guard isTabMoveMode != isEnabled else { return }
        isTabMoveMode = isEnabled
        reloadTabs()
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
        saveCurrentFolderState()
        selectedFolderID = id
        store.saveSelectedFolderID(id)
        loadSelectedFolder()
    }

    @objc private func tabClicked(_ sender: NSButton) {
        guard folders.indices.contains(sender.tag) else { return }
        selectFolderTab(index: sender.tag)
    }

    private func selectFolderTab(index: Int) {
        guard folders.indices.contains(index) else { return }
        saveCurrentFolderState()
        let id = folders[index].id
        selectedFolderID = id
        store.saveSelectedFolderID(id)
        if let index = folders.firstIndex(where: { $0.id == id }) {
            folderButton.selectItem(at: index)
        }
        loadSelectedFolder()
    }

    private func openGridItem(at indexPath: IndexPath) {
        guard shownFiles.indices.contains(indexPath.item) else { return }
        let entry = shownFiles[indexPath.item]
        if entry.isDirectory {
            enterFolder(entry.url)
        } else {
            NSWorkspace.shared.open(entry.url)
        }
    }

    private func enterFolder(_ url: URL) {
        guard currentFolderURL != url else { return }
        if let currentFolderURL {
            navigationStack.append(currentFolderURL)
        }
        currentFolderURL = url
        saveCurrentFolderState()
        reloadFiles(from: url)
        applyFilters()
    }

    private func dropDestinationForGrid(indexPath: IndexPath?) -> URL? {
        guard let indexPath, shownFiles.indices.contains(indexPath.item) else {
            return currentFolderURL
        }
        let entry = shownFiles[indexPath.item]
        return entry.isDirectory ? entry.url : currentFolderURL
    }

    private func dropDestinationForList(row: Int?) -> URL? {
        guard let row,
              row >= 0,
              let node = outlineView.item(atRow: row) as? FileNode else {
            return currentFolderURL
        }
        return node.entry.isDirectory ? node.entry.url : currentFolderURL
    }

    private func handleGridDropHover(indexPath: IndexPath?) {
        guard let indexPath,
              shownFiles.indices.contains(indexPath.item),
              shownFiles[indexPath.item].isDirectory else {
            cancelDropFolderHover()
            return
        }
        scheduleDropFolderHover(url: shownFiles[indexPath.item].url)
    }

    private func handleListDropHover(row: Int?) {
        guard let row,
              row >= 0,
              let node = outlineView.item(atRow: row) as? FileNode,
              node.entry.isDirectory else {
            cancelDropFolderHover()
            return
        }
        scheduleDropFolderHover(url: node.entry.url)
    }

    private func scheduleDropFolderHover(url: URL) {
        guard hoveredDropFolderURL != url else { return }
        cancelDropFolderHover()
        hoveredDropFolderURL = url
        flashDropFolder(url: url)

        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.hoveredDropFolderURL == url else { return }
            self.enterFolder(url)
            self.hoveredDropFolderURL = nil
            self.hoverFolderWorkItem = nil
        }
        hoverFolderWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75, execute: workItem)
    }

    private func cancelDropFolderHover() {
        hoverFolderWorkItem?.cancel()
        hoverFolderWorkItem = nil
        hoveredDropFolderURL = nil
    }

    private func flashDropFolder(url: URL) {
        if settings.viewMode == .grid,
           let index = shownFiles.firstIndex(where: { $0.url == url }),
           let item = collectionView.item(at: IndexPath(item: index, section: 0)) {
            flashView(item.view)
            return
        }

        for row in 0..<outlineView.numberOfRows {
            guard let node = outlineView.item(atRow: row) as? FileNode,
                  node.entry.url == url,
                  let view = outlineView.view(atColumn: 0, row: row, makeIfNecessary: false) else {
                continue
            }
            flashView(view)
            return
        }
    }

    private func flashView(_ view: NSView) {
        view.wantsLayer = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            view.animator().alphaValue = 0.45
        } completionHandler: {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.16
                view.animator().alphaValue = 1.0
            }
        }
    }

    @objc private func revealFolderTab(_ sender: NSMenuItem) {
        guard folders.indices.contains(sender.tag), let url = store.resolve(folders[sender.tag]) else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func resetFolderTabToRoot(_ sender: NSMenuItem) {
        guard folders.indices.contains(sender.tag) else { return }
        resetFolderStateToRoot(id: folders[sender.tag].id)
    }

    @objc private func deleteFolderTab(_ sender: NSMenuItem) {
        guard folders.indices.contains(sender.tag) else { return }
        let removed = folders.remove(at: sender.tag)
        folderNavigationStates.removeValue(forKey: removed.id)
        if selectedFolderID == removed.id {
            selectedFolderID = folders.first?.id
            store.saveSelectedFolderID(selectedFolderID)
        }
        store.saveFolders(folders)
        reloadFolderMenu()
        loadSelectedFolder()
    }

    @objc private func togglePin() {
        isPinned.toggle()
        pinButton.contentTintColor = isPinned ? .controlAccentColor : nil
    }

    @objc private func goBack() {
        guard let previous = navigationStack.popLast() else { return }
        currentFolderURL = previous
        saveCurrentFolderState()
        reloadFiles(from: previous)
        applyFilters()
    }

    @objc private func goToNavigationLevel(_ sender: NSButton) {
        let urls = levelDotURLs()
        guard urls.indices.contains(sender.tag) else { return }
        let targetURL = urls[sender.tag]

        currentFolderURL = targetURL
        navigationStack = Array(urls.prefix(sender.tag))
        saveCurrentFolderState()
        reloadFiles(from: targetURL)
        applyFilters()
    }

    @objc private func goRoot() {
        guard let selectedRootURL else { return }
        currentFolderURL = selectedRootURL
        navigationStack = []
        saveCurrentFolderState()
        reloadFiles(from: selectedRootURL)
        applyFilters()
    }

    @objc private func refreshFiles() {
        guard let currentFolderURL else { return }
        reloadFiles(from: currentFolderURL)
        applyFilters()
    }

    @objc private func viewModeChanged() {
        settings.viewMode = FileViewMode.allCases[max(0, viewModeControl.selectedSegment)]
        store.saveSettings(settings)
        updateContentMode()
        refreshCollection()
    }

    @objc private func openSettings() {
        settingsPanel.update(settings: settings)
        if let screen = panel.screen {
            settingsPanel.setFrameOrigin(NSPoint(
                x: screen.visibleFrame.midX - settingsPanel.frame.width / 2,
                y: screen.visibleFrame.midY - settingsPanel.frame.height / 2
            ))
        } else {
            settingsPanel.center()
        }
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
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if event.keyCode == 49 {
                self.previewSelected()
                return nil
            }
            if flags.contains(.command), event.keyCode == 8 {
                self.copySelectedFiles()
                return nil
            }
            if flags.contains(.command), event.keyCode == 9 {
                self.pasteFilesIntoCurrentFolder()
                return nil
            }
            if flags.contains(.command), event.keyCode == 51 {
                self.trashSelectedFiles()
                return nil
            }
            if event.keyCode == 36 {
                self.renameSelectedFile()
                return nil
            }
            if event.keyCode == 53 {
                self.hideWindow()
                return nil
            }
            return event
        }
    }

    private func installMouseMonitor() {
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self, self.isTabMoveMode, self.panel.isVisible else { return event }
            guard event.window === self.panel else {
                self.setTabMoveMode(false)
                return event
            }

            let point = self.tabBarView.convert(event.locationInWindow, from: nil)
            if !self.tabBarView.bounds.contains(point) {
                self.setTabMoveMode(false)
            }
            return event
        }
    }

    private func selectedPreviewURL() -> URL? {
        guard let entry = primarySelectedEntry() else { return nil }
        return entry.isDirectory ? nil : entry.url
    }

    @objc private func previewSelected() {
        guard selectedPreviewURL() != nil else { return }
        if let panel = QLPreviewPanel.shared() {
            panel.dataSource = self
            panel.delegate = self
            positionPreviewPanel(panel)
            panel.reloadData()
            panel.makeKeyAndOrderFront(nil)
        }
    }

    private func updatePreviewPanelForSelectionChange() {
        guard QLPreviewPanel.sharedPreviewPanelExists(),
              let panel = QLPreviewPanel.shared(),
              panel.isVisible else {
            return
        }

        if selectedPreviewURL() == nil {
            panel.orderOut(nil)
            return
        }

        panel.dataSource = self
        panel.delegate = self
        panel.reloadData()
        panel.makeKeyAndOrderFront(nil)
    }

    private func positionPreviewPanel(_ panel: QLPreviewPanel) {
        guard let screen = screenContainingMouse() ?? self.panel.screen ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        let width = min(max(panel.frame.width, 720), visible.width * 0.72)
        let height = min(max(panel.frame.height, 520), visible.height * 0.72)
        let frame = NSRect(
            x: visible.midX - width / 2,
            y: visible.midY - height / 2,
            width: width,
            height: height
        )
        panel.setFrame(frame, display: false)
    }

    private func selectedURLs() -> [URL] {
        selectedEntries().map(\.url)
    }

    @objc private func revealSelectedInFinder() {
        let urls = selectedURLs()
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    @objc private func copySelectedFiles() {
        let urls = selectedURLs()
        guard !urls.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects(urls as [NSURL])
    }

    @objc private func copySelectedPaths() {
        let paths = selectedURLs().map(\.path).joined(separator: "\n")
        guard !paths.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(paths, forType: .string)
    }

    @objc private func pasteFilesIntoCurrentFolder() {
        guard currentFolderURL != nil else { return }
        let pasteboard = NSPasteboard.general
        let items = FilePasteboardReader.fileURLs(from: pasteboard)
        guard !items.isEmpty else { return }
        _ = importFiles(items)
    }

    @discardableResult
    private func importFiles(_ urls: [URL]) -> Bool {
        importFiles(urls, to: currentFolderURL)
    }

    @discardableResult
    private func importFiles(_ urls: [URL], to folderURL: URL?) -> Bool {
        guard let folderURL else { return false }
        var didImport = false

        for source in urls {
            guard source.deletingLastPathComponent() != folderURL else { continue }
            guard let destination = resolvedImportDestination(for: source, in: folderURL) else { continue }
            do {
                try FileManager.default.copyItem(at: source, to: destination)
                didImport = true
            } catch {
                showAlert(title: "复制失败", message: error.localizedDescription)
            }
        }
        if didImport {
            if folderURL == currentFolderURL {
                refreshFiles()
            }
        }
        return didImport
    }

    private enum DuplicateChoice {
        case replace
        case keepBoth
        case skip
    }

    private func resolvedImportDestination(for source: URL, in folder: URL) -> URL? {
        let destination = folder.appendingPathComponent(source.lastPathComponent)
        guard FileManager.default.fileExists(atPath: destination.path) else {
            return destination
        }

        switch askDuplicateChoice(fileName: source.lastPathComponent) {
        case .replace:
            try? FileManager.default.trashItem(at: destination, resultingItemURL: nil)
            return destination
        case .keepBoth:
            return uniqueDestination(for: source.lastPathComponent, in: folder)
        case .skip:
            return nil
        }
    }

    private func askDuplicateChoice(fileName: String) -> DuplicateChoice {
        let alert = NSAlert()
        alert.messageText = "已存在同名项目"
        alert.informativeText = "“\(fileName)”已经存在于当前文件夹中。"
        alert.addButton(withTitle: "替换")
        alert.addButton(withTitle: "保留两者")
        alert.addButton(withTitle: "跳过")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return .replace
        case .alertSecondButtonReturn:
            return .keepBoth
        default:
            return .skip
        }
    }

    private func uniqueDestination(for name: String, in folder: URL) -> URL {
        var destination = folder.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: destination.path) else { return destination }

        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var index = 2
        repeat {
            let nextName = ext.isEmpty ? "\(base) \(index)" : "\(base) \(index).\(ext)"
            destination = folder.appendingPathComponent(nextName)
            index += 1
        } while FileManager.default.fileExists(atPath: destination.path)
        return destination
    }

    @objc private func trashSelectedFiles() {
        let urls = selectedURLs()
        guard !urls.isEmpty else { return }
        for url in urls {
            try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
        }
        refreshFiles()
    }

    @objc private func renameSelectedFile() {
        guard let entry = primarySelectedEntry() else { return }
        let alert = NSAlert()
        alert.messageText = "重命名"
        alert.informativeText = entry.name
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        field.stringValue = entry.name
        alert.accessoryView = field
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "取消")

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let newName = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newName.isEmpty, newName != entry.name else { return }
        let destination = entry.url.deletingLastPathComponent().appendingPathComponent(newName)
        do {
            try FileManager.default.moveItem(at: entry.url, to: destination)
            refreshFiles()
        } catch {
            showAlert(title: "重命名失败", message: error.localizedDescription)
        }
    }

    @objc private func showSelectedInfo() {
        guard let entry = primarySelectedEntry() else { return }
        let values = try? entry.url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .creationDateKey])
        let size = values?.fileSize.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) } ?? "未知"
        let modified = values?.contentModificationDate.map { DateFormatter.localizedString(from: $0, dateStyle: .medium, timeStyle: .short) } ?? "未知"

        let alert = NSAlert()
        alert.messageText = entry.name
        alert.informativeText = "类型：\(entry.kind.rawValue)\n大小：\(size)\n修改时间：\(modified)\n路径：\(entry.url.path)"
        alert.addButton(withTitle: "好")
        alert.runModal()
    }

    @objc private func openWithMenuItem(_ sender: NSMenuItem) {
        guard let appURL = sender.representedObject as? URL,
              let fileURL = primarySelectedEntry()?.url else { return }
        NSWorkspace.shared.open([fileURL], withApplicationAt: appURL, configuration: NSWorkspace.OpenConfiguration())
    }

    @objc private func quickActionZip() {
        guard let entry = primarySelectedEntry() else { return }
        let destination = entry.url.deletingLastPathComponent().appendingPathComponent("\((entry.name as NSString).deletingPathExtension).zip")
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        task.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent", entry.url.path, destination.path]
        try? task.run()
    }

    private func fileMenu() -> NSMenu {
        let menu = NSMenu()

        let reveal = NSMenuItem(title: "在访达中显示", action: #selector(revealSelectedInFinder), keyEquivalent: "")
        reveal.target = self
        menu.addItem(reveal)

        let openWith = NSMenuItem(title: "打开方式", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        if let url = primarySelectedEntry()?.url {
            let apps = NSWorkspace.shared.urlsForApplications(toOpen: url)
            for app in apps.prefix(8) {
                let item = NSMenuItem(title: app.deletingPathExtension().lastPathComponent, action: #selector(openWithMenuItem(_:)), keyEquivalent: "")
                item.representedObject = app
                item.target = self
                submenu.addItem(item)
            }
        }
        if submenu.items.isEmpty {
            submenu.addItem(NSMenuItem(title: "没有可用应用", action: nil, keyEquivalent: ""))
        }
        openWith.submenu = submenu
        menu.addItem(openWith)

        let rename = NSMenuItem(title: "重命名", action: #selector(renameSelectedFile), keyEquivalent: "")
        rename.target = self
        menu.addItem(rename)

        let copyPath = NSMenuItem(title: "复制路径", action: #selector(copySelectedPaths), keyEquivalent: "")
        copyPath.target = self
        menu.addItem(copyPath)

        let info = NSMenuItem(title: "获取信息", action: #selector(showSelectedInfo), keyEquivalent: "")
        info.target = self
        menu.addItem(info)

        let trash = NSMenuItem(title: "删除到废纸篓", action: #selector(trashSelectedFiles), keyEquivalent: "")
        trash.target = self
        menu.addItem(trash)

        let quick = NSMenuItem(title: "快速操作", action: nil, keyEquivalent: "")
        let quickMenu = NSMenu()
        let zip = NSMenuItem(title: "压缩为 ZIP", action: #selector(quickActionZip), keyEquivalent: "")
        zip.target = self
        quickMenu.addItem(zip)
        quick.submenu = quickMenu
        menu.addItem(quick)

        return menu
    }

    private func applySettings(_ newSettings: AppSettings) {
        settings = newSettings
        store.saveSettings(settings)
        panel.alphaValue = settings.opacity
        edgePanels.forEach { $0.backgroundColor = settings.showEdgeTrigger ? NSColor.controlAccentColor.withAlphaComponent(0.18) : .clear }
        applyItemSize()
        updateContentMode()
        updatePathLabel()
        rebuildEdgeTriggers()
        positionPanel(anchor: settings.sidebarPosition, screen: screenContainingMouse() ?? NSScreen.main)
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
        updatePreviewPanelForSelectionChange()
    }

    func collectionView(_ collectionView: NSCollectionView, didDeselectItemsAt indexPaths: Set<IndexPath>) {
        previewButton.isEnabled = selectedPreviewURL() != nil
        updatePreviewPanelForSelectionChange()
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
        nil
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

extension SidebarWindowController: NSOutlineViewDataSource, NSOutlineViewDelegate {
    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        guard let node = item as? FileNode else {
            return listRootNodes.count
        }
        return loadChildren(for: node).count
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        guard let node = item as? FileNode else {
            return listRootNodes[index]
        }
        return loadChildren(for: node)[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        guard let node = item as? FileNode else { return false }
        return node.entry.isDirectory
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let node = item as? FileNode else { return nil }
        let view = outlineView.makeView(withIdentifier: FileListRowView.identifier, owner: self) as? FileListRowView ?? FileListRowView()
        view.identifier = FileListRowView.identifier
        view.configure(entry: node.entry, depth: outlineView.level(forItem: item))
        return view
    }

    func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> NSPasteboardWriting? {
        guard let node = item as? FileNode else { return nil }
        return node.entry.url as NSURL
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        previewButton.isEnabled = selectedPreviewURL() != nil
        updateLevelDots()
        updatePreviewPanelForSelectionChange()
    }

    func outlineViewItemDidExpand(_ notification: Notification) {
        guard let node = notification.userInfo?["NSObject"] as? FileNode else { return }
        setListNode(node, expanded: true)
        updateLevelDots()
    }

    func outlineViewItemDidCollapse(_ notification: Notification) {
        guard let node = notification.userInfo?["NSObject"] as? FileNode else { return }
        setListNode(node, expanded: false)
        updateLevelDots()
    }

    @objc private func outlineDoubleClicked() {
        let row = outlineView.clickedRow >= 0 ? outlineView.clickedRow : outlineView.selectedRow
        guard row >= 0, let node = outlineView.item(atRow: row) as? FileNode else { return }
        if node.entry.isDirectory {
            enterFolder(node.entry.url)
        } else {
            NSWorkspace.shared.open(node.entry.url)
        }
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

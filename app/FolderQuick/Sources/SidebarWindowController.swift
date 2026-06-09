import AppKit
import Quartz

final class FileHoverButton: NSButton {
    var onFileHover: ((Bool) -> Void)?
    var isFileDropHovered: Bool = false {
        didSet {
            contentTintColor = isFileDropHovered ? .controlAccentColor : nil
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes(FilePasteboardReader.supportedTypes)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForDraggedTypes(FilePasteboardReader.supportedTypes)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard !FolderQuickDragCancel.isCancelled else {
            isFileDropHovered = false
            onFileHover?(false)
            return []
        }
        return dragOperation(for: sender, hovering: true)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard !FolderQuickDragCancel.isCancelled else {
            isFileDropHovered = false
            onFileHover?(false)
            return []
        }
        return dragOperation(for: sender, hovering: true)
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        isFileDropHovered = false
        onFileHover?(false)
        FolderQuickDragCancel.reset()
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        isFileDropHovered = false
        onFileHover?(false)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        isFileDropHovered = false
        onFileHover?(false)
        FolderQuickDragCancel.reset()
        return false
    }

    private func dragOperation(for sender: NSDraggingInfo, hovering: Bool) -> NSDragOperation {
        guard !FilePasteboardReader.fileURLs(from: sender.draggingPasteboard).isEmpty else {
            isFileDropHovered = false
            onFileHover?(false)
            return []
        }
        isFileDropHovered = hovering
        onFileHover?(hovering)
        return FileImportOperation.current().dragOperation
    }
}

final class SidebarWindowController: NSObject {
    private let store = FolderStore.shared
    private let loader = FileLoader()
    private var settings: AppSettings
    private lazy var settingsPanel = SettingsPanel(settings: settings)

    private var panel: NSPanel!
    private var edgePanels: [NSPanel] = []
    private var rootView = NSVisualEffectView()
    private var sidebarButton = NSButton()
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
    private var sidebarOutlineView = NSOutlineView()
    private var sidebarScrollView = NSScrollView()
    private var fileContentView = NSView()
    private var sidebarWidthConstraint: NSLayoutConstraint?
    private var transferProgressPanel = FileTransferProgressPanel()
    private var countLabel = NSTextField(labelWithString: "0 项")
    private var pathLabel = NSTextField(labelWithString: "未选择文件夹")
    private var levelDotsStack = NSStackView()
    private var settingsButton = NSButton()
    private var emptyLabel = NSTextField(labelWithString: "添加一个常用文件夹后开始使用")
    private var hideWorkItem: DispatchWorkItem?
    private var edgeHideWorkItem: DispatchWorkItem?
    private var lastEdgeShowDate: Date?
    private var hoverFolderWorkItem: DispatchWorkItem?
    private var hoveredDropFolderURL: URL?
    private var hoverTabWorkItem: DispatchWorkItem?
    private var hoveredDropTabID: UUID?
    private var hoverBackWorkItem: DispatchWorkItem?
    private var highlightedDropFolderURL: URL?
    private var highlightedDropTabID: UUID?
    private var keyMonitor: Any?
    private var mouseMonitor: Any?
    private var dragCancelMonitors: [Any] = []
    private let transferQueue = DispatchQueue(label: "local.folderquick.file-transfer", qos: .userInitiated)
    private let fileLoadQueue = DispatchQueue(label: "local.folderquick.file-load", qos: .userInitiated)
    private let filterQueue = DispatchQueue(label: "local.folderquick.file-filter", qos: .userInitiated)
    private var fileLoadGeneration = 0
    private var filterGeneration = 0

    private var folders: [FolderEntry] = []
    private var selectedFolderID: UUID?
    private var selectedRootURL: URL?
    private var currentFolderURL: URL?
    private var navigationStack: [URL] = []
    private var allFiles: [FileEntry] = []
    private var shownFiles: [FileEntry] = []
    private var listRootNodes: [FileNode] = []
    private var sidebarRootNodes: [FileNode] = []
    private var folderNavigationStates: [UUID: FolderNavigationState] = [:]
    private var isPinned = false
    private var isTabMoveMode = false

    private struct FolderNavigationState {
        var rootURL: URL
        var currentURL: URL
        var stack: [URL]
        var expandedListPaths: Set<String>
    }

    private struct FileImportTask {
        let source: URL
        let destination: URL
        let operation: FileImportOperation
    }

    override init() {
        settings = store.loadSettings()
        super.init()
        AppLogger.info("SidebarWindowController init start")
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
        installDragCancelMonitors()
        reloadFolderMenu()
        loadSelectedFolder()
        AppLogger.info("SidebarWindowController init finished")
    }

    deinit {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        if let mouseMonitor {
            NSEvent.removeMonitor(mouseMonitor)
        }
        dragCancelMonitors.forEach { NSEvent.removeMonitor($0) }
    }

    func showWindow() {
        positionPanel(anchor: settings.sidebarPosition, screen: screenContainingMouse() ?? NSScreen.main)
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        lastEdgeShowDate = Date()
    }

    private func showWindow(anchor: WindowAnchor, screen: NSScreen) {
        positionPanel(anchor: anchor, screen: screen)
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        lastEdgeShowDate = Date()
    }

    func toggleWindow() {
        if panel.isVisible {
            hideWindow()
        } else {
            showWindow()
        }
    }

    private func hideWindow() {
        edgeHideWorkItem?.cancel()
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
        panel.minSize = NSSize(width: 360, height: 420)
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
            self?.handleEdgeTrigger(anchor: anchor, fallbackScreen: screen)
        }
        triggerView.onMouseExit = { [weak self] in
            self?.cancelPendingEdgeHide()
        }
        edgePanel.contentView = triggerView
        return edgePanel
    }

    private func handleEdgeTrigger(anchor: WindowAnchor, fallbackScreen: NSScreen) {
        if panel.isVisible, isPinned {
            if settings.hidePinnedWindowOnEdgeTrigger == true {
                schedulePinnedEdgeHide()
            }
            return
        }

        let targetScreen = screenContainingMouse() ?? fallbackScreen
        showWindow(anchor: anchor, screen: targetScreen)
    }

    private func schedulePinnedEdgeHide() {
        if let lastEdgeShowDate, Date().timeIntervalSince(lastEdgeShowDate) < 0.9 {
            return
        }

        edgeHideWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.hideWindow()
        }
        edgeHideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7, execute: workItem)
    }

    private func cancelPendingEdgeHide() {
        edgeHideWorkItem?.cancel()
        edgeHideWorkItem = nil
    }

    private func rebuildEdgeTriggers() {
        AppLogger.info("rebuildEdgeTriggers start enabled=\(settings.edgeTriggerEnabled) positions=\(settings.triggerPositions.map(\.rawValue).joined(separator: ","))")
        edgePanels.forEach { $0.orderOut(nil) }
        edgePanels = []

        guard settings.edgeTriggerEnabled else {
            AppLogger.info("rebuildEdgeTriggers skipped disabled")
            return
        }
        for screen in NSScreen.screens {
            for anchor in settings.triggerPositions {
                let trigger = makeEdgeTrigger(anchor: anchor, screen: screen)
                edgePanels.append(trigger)
                trigger.orderFrontRegardless()
            }
        }
        AppLogger.info("rebuildEdgeTriggers finished count=\(edgePanels.count)")
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
        tabBarView.onHoverFileTab = { [weak self] index in
            self?.handleTabDropHover(index: index)
        }
        tabBarView.onDropFilesOnTab = { [weak self] urls, index, operation in
            self?.importFiles(urls, to: self?.dropDestinationForTab(index: index), operation: operation) ?? false
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

        sidebarButton = iconButton("sidebar.left", action: #selector(toggleSidebarFromToolbar))
        updateSidebarButtonState()
        backButton = hoverIconButton("chevron.left", action: #selector(goBack))
        (backButton as? FileHoverButton)?.onFileHover = { [weak self] isHovering in
            self?.handleBackDropHover(isHovering: isHovering)
        }
        viewModeControl.selectedSegment = FileViewMode.allCases.firstIndex(of: settings.viewMode) ?? 0
        viewModeControl.target = self
        viewModeControl.action = #selector(viewModeChanged)

        let leftStack = NSStackView(views: [sidebarButton, backButton, searchField])
        leftStack.orientation = .horizontal
        leftStack.alignment = .centerY
        leftStack.spacing = 8
        leftStack.translatesAutoresizingMaskIntoConstraints = false

        viewModeControl.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(leftStack)
        bar.addSubview(viewModeControl)

        NSLayoutConstraint.activate([
            leftStack.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 12),
            leftStack.trailingAnchor.constraint(lessThanOrEqualTo: viewModeControl.leadingAnchor, constant: -12),
            leftStack.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            viewModeControl.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -14),
            viewModeControl.centerYAnchor.constraint(equalTo: bar.centerYAnchor)
        ])

        return bar
    }

    private func makeContentView() -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let layout = NSCollectionViewFlowLayout()
        layout.itemSize = itemSize()
        layout.sectionInset = NSEdgeInsets(top: 16, left: 34, bottom: 16, right: 34)
        layout.minimumInteritemSpacing = settings.iconSpacing
        layout.minimumLineSpacing = max(2, settings.iconSpacing)

        collectionView.collectionViewLayout = layout
        collectionView.register(FileItemView.self, forItemWithIdentifier: FileItemView.identifier)
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.isSelectable = true
        collectionView.allowsMultipleSelection = true
        collectionView.backgroundColors = [.clear]
        collectionView.setDraggingSourceOperationMask([.copy, .move], forLocal: false)
        collectionView.menuProvider = { [weak self] in
            self?.primarySelectedEntry() == nil ? nil : self?.fileMenu()
        }
        collectionView.emptyMenuProvider = { [weak self] in
            self?.emptyAreaMenu()
        }
        collectionView.onDoubleClickItem = { [weak self] indexPath in
            self?.openGridItem(at: indexPath)
        }
        collectionView.onDropFiles = { [weak self] urls, indexPath, operation in
            guard let self else { return false }
            return self.importFiles(urls, to: self.dropDestinationForGrid(indexPath: indexPath), operation: operation)
        }
        collectionView.onHoverItem = { [weak self] indexPath in
            self?.handleGridDropHover(indexPath: indexPath)
        }
        collectionView.onEmptyClick = { [weak self] in
            self?.closePreviewPanel()
        }
        collectionView.dragURLsProvider = { [weak self] in
            self?.selectedURLs() ?? []
        }
        collectionView.isDropTargetProvider = { [weak self] indexPath in
            guard let self, self.shownFiles.indices.contains(indexPath.item) else { return false }
            return self.shownFiles[indexPath.item].isDirectory
        }
        scrollView.onDropFiles = { [weak self] urls, operation in
            self?.importFiles(urls, operation: operation) ?? false
        }

        scrollView.documentView = collectionView
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        configureListColumns()
        outlineView.rowHeight = 30
        outlineView.backgroundColor = .clear
        outlineView.columnAutoresizingStyle = .noColumnAutoresizing
        outlineView.delegate = self
        outlineView.dataSource = self
        outlineView.target = self
        outlineView.doubleAction = #selector(outlineDoubleClicked)
        outlineView.menuProvider = { [weak self] in
            self?.fileMenu()
        }
        outlineView.emptyMenuProvider = { [weak self] in
            self?.emptyAreaMenu()
        }
        outlineView.onDropFiles = { [weak self] urls, row, operation in
            guard let self else { return false }
            return self.importFiles(urls, to: self.dropDestinationForList(row: row), operation: operation)
        }
        outlineView.onHoverRow = { [weak self] row in
            self?.handleListDropHover(row: row)
        }
        outlineView.onEmptyClick = { [weak self] in
            self?.closePreviewPanel()
        }
        outlineView.setDraggingSourceOperationMask([.copy, .move], forLocal: false)
        outlineView.setDraggingSourceOperationMask([.copy, .move], forLocal: true)
        listScrollView.onDropFiles = { [weak self] urls, operation in
            self?.importFiles(urls, operation: operation) ?? false
        }
        outlineView.usesAlternatingRowBackgroundColors = false
        outlineView.allowsMultipleSelection = true
        listScrollView.documentView = outlineView
        listScrollView.drawsBackground = false
        listScrollView.hasVerticalScroller = true
        listScrollView.hasHorizontalScroller = false
        listScrollView.autohidesScrollers = true
        listScrollView.scrollerStyle = .overlay
        listScrollView.translatesAutoresizingMaskIntoConstraints = false

        let sidebarColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("sidebar"))
        sidebarColumn.title = "文件夹"
        sidebarOutlineView.addTableColumn(sidebarColumn)
        sidebarOutlineView.outlineTableColumn = sidebarColumn
        sidebarOutlineView.headerView = nil
        sidebarOutlineView.rowHeight = 28
        sidebarOutlineView.backgroundColor = .clear
        sidebarOutlineView.delegate = self
        sidebarOutlineView.dataSource = self
        sidebarOutlineView.target = self
        sidebarOutlineView.doubleAction = #selector(sidebarDoubleClicked)
        sidebarOutlineView.selectionHighlightStyle = .regular
        sidebarScrollView.documentView = sidebarOutlineView
        sidebarScrollView.drawsBackground = false
        sidebarScrollView.hasVerticalScroller = true
        sidebarScrollView.hasHorizontalScroller = false
        sidebarScrollView.autohidesScrollers = true
        sidebarScrollView.scrollerStyle = .overlay
        sidebarScrollView.translatesAutoresizingMaskIntoConstraints = false

        emptyLabel.font = .systemFont(ofSize: 16, weight: .medium)
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.alignment = .center
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false

        fileContentView.translatesAutoresizingMaskIntoConstraints = false
        fileContentView.addSubview(scrollView)
        fileContentView.addSubview(listScrollView)

        sidebarWidthConstraint = sidebarScrollView.widthAnchor.constraint(equalToConstant: settings.showSidebar ? 190 : 0)

        container.addSubview(sidebarScrollView)
        container.addSubview(fileContentView)
        container.addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            sidebarScrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            sidebarScrollView.topAnchor.constraint(equalTo: container.topAnchor),
            sidebarScrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            sidebarWidthConstraint!,
            fileContentView.leadingAnchor.constraint(equalTo: sidebarScrollView.trailingAnchor),
            fileContentView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            fileContentView.topAnchor.constraint(equalTo: container.topAnchor),
            fileContentView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: fileContentView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: fileContentView.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: fileContentView.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: fileContentView.bottomAnchor),
            listScrollView.leadingAnchor.constraint(equalTo: fileContentView.leadingAnchor),
            listScrollView.trailingAnchor.constraint(equalTo: fileContentView.trailingAnchor),
            listScrollView.topAnchor.constraint(equalTo: fileContentView.topAnchor),
            listScrollView.bottomAnchor.constraint(equalTo: fileContentView.bottomAnchor),
            emptyLabel.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])

        updateContentMode()

        return container
    }

    private func configureListColumns() {
        AppLogger.info("configureListColumns start visibleColumns=\(settings.listInfoColumns.map(\.rawValue).joined(separator: ","))")

        let nameIdentifier = NSUserInterfaceItemIdentifier("name")
        let nameColumn = outlineView.tableColumns.first(where: { $0.identifier == nameIdentifier }) ?? NSTableColumn(identifier: nameIdentifier)
        if !outlineView.tableColumns.contains(nameColumn) {
            outlineView.addTableColumn(nameColumn)
        }
        nameColumn.title = sortTitle("名称", mode: .name)
        nameColumn.minWidth = 220
        nameColumn.width = max(nameColumn.width, 320)
        nameColumn.resizingMask = .userResizingMask
        nameColumn.isHidden = false
        outlineView.outlineTableColumn = nameColumn

        for infoColumn in ListInfoColumn.allCases {
            let identifier = NSUserInterfaceItemIdentifier(infoColumn.rawValue)
            let column = outlineView.tableColumns.first(where: { $0.identifier == identifier }) ?? NSTableColumn(identifier: identifier)
            if !outlineView.tableColumns.contains(column) {
                outlineView.addTableColumn(column)
            }
            column.title = sortTitle(infoColumn.rawValue, mode: sortMode(for: infoColumn))
            column.minWidth = infoColumn == .size ? 78 : 110
            column.width = max(column.width, infoColumn == .size ? 92 : 142)
            column.resizingMask = .userResizingMask
            column.isHidden = !settings.listInfoColumns.contains(infoColumn)
        }

        if let headerView = outlineView.headerView as? FolderQuickTableHeaderView {
            headerView.menuProvider = { [weak self] in
                self?.emptyAreaMenu()
            }
        } else {
            let headerView = FolderQuickTableHeaderView()
            headerView.menuProvider = { [weak self] in
                self?.emptyAreaMenu()
            }
            outlineView.headerView = headerView
        }

        outlineView.noteNumberOfRowsChanged()
        AppLogger.info("configureListColumns finished columns=\(outlineView.tableColumns.map { "\($0.identifier.rawValue):\($0.isHidden ? "hidden" : "visible")" }.joined(separator: ","))")
    }

    private func updateListColumnTitles() {
        for column in outlineView.tableColumns {
            if column.identifier.rawValue == "name" {
                column.title = sortTitle("名称", mode: .name)
            } else if let infoColumn = ListInfoColumn(rawValue: column.identifier.rawValue) {
                column.title = sortTitle(infoColumn.rawValue, mode: sortMode(for: infoColumn))
            }
        }
    }

    private func sortTitle(_ title: String, mode: FileSortMode) -> String {
        guard settings.sortMode == mode else { return title }
        return "\(title) \(settings.sortAscending ? "⌃" : "⌄")"
    }

    private func sortMode(for column: ListInfoColumn) -> FileSortMode {
        switch column {
        case .kind:
            return .kind
        case .dateModified:
            return .dateModified
        case .dateCreated:
            return .dateCreated
        case .size:
            return .size
        }
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

    private func hoverIconButton(_ systemName: String, action: Selector) -> NSButton {
        let button = FileHoverButton()
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
        let corner = 34.0
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
            button.onMovePressChanged = { [weak self] isPressed in
                self?.setTabMoveMode(isPressed)
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
        DispatchQueue.main.async { [weak self] in
            self?.scrollSelectedTabIntoView()
        }
    }

    private func scrollSelectedTabIntoView() {
        guard let selectedFolderID,
              let index = folders.firstIndex(where: { $0.id == selectedFolderID }),
              let button = tabBarView.subviews
                .compactMap({ $0 as? FolderTabButton })
                .first(where: { $0.folderIndex == index }) else { return }
        tabScrollView.scrollTabRectToVisible(button.frame)
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
        reloadFiles(from: currentFolderURL ?? url, rebuildSidebar: true)
        reloadTabs()
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
        reloadFiles(from: rootURL, rebuildSidebar: true)
        reloadTabs()
    }

    private func refreshCollection() {
        AppLogger.info("refreshCollection start all=\(allFiles.count) shown=\(shownFiles.count) mode=\(settings.viewMode.rawValue)")
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
        AppLogger.info("refreshCollection finished")
    }

    private func reloadFiles(from url: URL, rebuildSidebar: Bool = false) {
        AppLogger.info("reloadFiles requested path=\(url.path) rebuildSidebar=\(rebuildSidebar)")
        fileLoadGeneration += 1
        filterGeneration += 1
        let generation = fileLoadGeneration
        let loader = self.loader

        allFiles = []
        shownFiles = []
        listRootNodes = []
        collectionView.reloadData()
        outlineView.reloadData()
        countLabel.stringValue = "读取中"
        emptyLabel.stringValue = "正在读取文件..."
        emptyLabel.isHidden = false

        fileLoadQueue.async { [weak self] in
            AppLogger.info("reloadFiles background start path=\(url.path)")
            let files = loader.loadFiles(in: url)
            AppLogger.info("reloadFiles background finished path=\(url.path) count=\(files.count)")
            DispatchQueue.main.async {
                guard let self,
                      self.fileLoadGeneration == generation,
                      self.currentFolderURL == url else {
                    AppLogger.info("reloadFiles result ignored path=\(url.path)")
                    return
                }
                self.allFiles = files
                if rebuildSidebar {
                    self.rebuildSidebarNodes()
                }
                self.applyFilters()
            }
        }
    }

    private func rebuildSidebarNodes() {
        guard let selectedRootURL else {
            sidebarRootNodes = []
            sidebarOutlineView.reloadData()
            return
        }
        let rootEntry = FileEntry.make(url: selectedRootURL)
        sidebarRootNodes = [FileNode(entry: rootEntry)]
        sidebarOutlineView.reloadData()
        if let root = sidebarRootNodes.first {
            sidebarOutlineView.expandItem(root)
        }
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
        let thumbnailSize = max(34, min(width * 0.78, width - 12))
        return NSSize(width: width, height: thumbnailSize * 0.9 + (width < 76 ? 38 : 54))
    }

    private func applyItemSize() {
        guard let layout = collectionView.collectionViewLayout as? NSCollectionViewFlowLayout else { return }
        layout.itemSize = itemSize()
        layout.minimumInteritemSpacing = settings.iconSpacing
        layout.minimumLineSpacing = max(2, settings.iconSpacing)
        layout.invalidateLayout()
    }

    private func updateContentMode() {
        let showList = settings.viewMode == .list
        scrollView.isHidden = showList
        listScrollView.isHidden = !showList
        sidebarScrollView.isHidden = !settings.showSidebar
        applySidebarWidth()
        viewModeControl.selectedSegment = FileViewMode.allCases.firstIndex(of: settings.viewMode) ?? 0
        updateSidebarButtonState()
        updateLevelDots()
    }

    private func applySidebarWidth() {
        sidebarWidthConstraint?.constant = settings.showSidebar ? min(220, max(170, panel.frame.width * 0.16)) : 0
        fileContentView.needsLayout = true
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

    private func loadSidebarChildren(for node: FileNode) -> [FileNode] {
        if let children = node.children {
            return children
        }
        guard node.entry.isDirectory else {
            node.children = []
            return []
        }
        let children = loader.loadFiles(in: node.entry.url)
            .filter(\.isDirectory)
            .map { FileNode(entry: $0, parent: node) }
        node.children = children
        return children
    }

    private func levelDotURLs() -> [URL] {
        navigationPathURLs()
    }

    private func selectedEntries() -> [FileEntry] {
        if settings.viewMode == .list {
            return selectedListRows().compactMap { row in
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

    private func selectedListRows() -> [Int] {
        outlineView.selectedRowIndexes.map { $0 }
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

    private func dropDestinationForTab(index: Int) -> URL? {
        guard folders.indices.contains(index),
              let rootURL = store.resolve(folders[index]) else {
            return nil
        }

        let id = folders[index].id
        if let state = folderNavigationStates[id],
           state.rootURL == rootURL,
           FileManager.default.fileExists(atPath: state.currentURL.path) {
            return state.currentURL
        }
        return rootURL
    }

    private func handleGridDropHover(indexPath: IndexPath?) {
        guard let indexPath,
              shownFiles.indices.contains(indexPath.item),
              shownFiles[indexPath.item].isDirectory else {
            cancelDropFolderHover()
            clearDropFolderHighlight()
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
            clearDropFolderHighlight()
            return
        }
        scheduleDropFolderHover(url: node.entry.url)
    }

    private func handleTabDropHover(index: Int?) {
        guard let index, folders.indices.contains(index) else {
            cancelDropTabHover()
            clearDropTabHighlight()
            return
        }
        scheduleDropTabHover(index: index)
    }

    private func handleBackDropHover(isHovering: Bool) {
        guard isHovering, !navigationStack.isEmpty else {
            cancelDropBackHover()
            return
        }
        scheduleDropBackHover()
    }

    private func scheduleDropFolderHover(url: URL) {
        guard hoveredDropFolderURL != url else { return }
        cancelDropFolderHover()
        hoveredDropFolderURL = url
        setDropFolderHighlight(url: url)

        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.hoveredDropFolderURL == url else { return }
            self.enterFolder(url)
            self.clearDropFolderHighlight()
            self.hoveredDropFolderURL = nil
            self.hoverFolderWorkItem = nil
        }
        hoverFolderWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: workItem)
    }

    private func cancelDropFolderHover() {
        hoverFolderWorkItem?.cancel()
        hoverFolderWorkItem = nil
        hoveredDropFolderURL = nil
    }

    private func scheduleDropTabHover(index: Int) {
        guard folders.indices.contains(index) else { return }
        let id = folders[index].id
        guard selectedFolderID != id else {
            cancelDropTabHover()
            return
        }
        guard hoveredDropTabID != id else { return }

        cancelDropTabHover()
        hoveredDropTabID = id
        setDropTabHighlight(index: index)

        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.hoveredDropTabID == id else { return }
            self.selectFolderTab(index: index)
            self.clearDropTabHighlight()
            self.hoveredDropTabID = nil
            self.hoverTabWorkItem = nil
        }
        hoverTabWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: workItem)
    }

    private func cancelDropTabHover() {
        hoverTabWorkItem?.cancel()
        hoverTabWorkItem = nil
        hoveredDropTabID = nil
    }

    private func scheduleDropBackHover() {
        guard hoverBackWorkItem == nil else { return }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.hoverBackWorkItem = nil
            guard !self.navigationStack.isEmpty else { return }
            self.goBack()
        }
        hoverBackWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: workItem)
    }

    private func cancelDropBackHover() {
        hoverBackWorkItem?.cancel()
        hoverBackWorkItem = nil
    }

    private func cancelActiveDragInteractions() {
        FolderQuickDragCancel.cancelCurrentDrag()
        cancelDropFolderHover()
        cancelDropTabHover()
        cancelDropBackHover()
        clearDropFolderHighlight()
        clearDropTabHighlight()
        (backButton as? FileHoverButton)?.isFileDropHovered = false
    }

    private func hasActiveDragInteraction() -> Bool {
        hoverFolderWorkItem != nil
            || hoverTabWorkItem != nil
            || hoverBackWorkItem != nil
            || highlightedDropFolderURL != nil
            || highlightedDropTabID != nil
            || ((backButton as? FileHoverButton)?.isFileDropHovered ?? false)
    }

    private func setDropFolderHighlight(url: URL) {
        if highlightedDropFolderURL == url { return }
        clearDropFolderHighlight()
        highlightedDropFolderURL = url
        setDropFolderHighlight(url: url, isHighlighted: true)
    }

    private func clearDropFolderHighlight() {
        guard let url = highlightedDropFolderURL else { return }
        setDropFolderHighlight(url: url, isHighlighted: false)
        highlightedDropFolderURL = nil
    }

    private func setDropFolderHighlight(url: URL, isHighlighted: Bool) {
        if let index = shownFiles.firstIndex(where: { $0.url == url }),
           let item = collectionView.item(at: IndexPath(item: index, section: 0)) as? FileItemView {
            item.isDropHovered = isHighlighted
        }

        for row in 0..<outlineView.numberOfRows {
            guard let node = outlineView.item(atRow: row) as? FileNode,
                  node.entry.url == url,
                  let view = outlineView.view(atColumn: 0, row: row, makeIfNecessary: false) as? FileListRowView else {
                continue
            }
            view.isDropHovered = isHighlighted
        }
    }

    private func setDropTabHighlight(index: Int) {
        guard folders.indices.contains(index) else { return }
        let id = folders[index].id
        if highlightedDropTabID == id { return }
        clearDropTabHighlight()
        highlightedDropTabID = id
        setDropTabHighlight(id: id, isHighlighted: true)
    }

    private func clearDropTabHighlight() {
        guard let id = highlightedDropTabID else { return }
        setDropTabHighlight(id: id, isHighlighted: false)
        highlightedDropTabID = nil
    }

    private func setDropTabHighlight(id: UUID, isHighlighted: Bool) {
        guard let index = folders.firstIndex(where: { $0.id == id }) else { return }
        tabBarView.subviews
            .compactMap { $0 as? FolderTabButton }
            .first(where: { $0.folderIndex == index })?
            .isDropHovered = isHighlighted
    }

    private func flashView(_ view: NSView) {
        if let button = view as? NSButton {
            button.contentTintColor = .controlAccentColor
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) {
                button.contentTintColor = nil
            }
            return
        }
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
    }

    @objc private func goToNavigationLevel(_ sender: NSButton) {
        let urls = levelDotURLs()
        guard urls.indices.contains(sender.tag) else { return }
        let targetURL = urls[sender.tag]

        currentFolderURL = targetURL
        navigationStack = Array(urls.prefix(sender.tag))
        saveCurrentFolderState()
        reloadFiles(from: targetURL)
    }

    @objc private func goRoot() {
        guard let selectedRootURL else { return }
        currentFolderURL = selectedRootURL
        navigationStack = []
        saveCurrentFolderState()
        reloadFiles(from: selectedRootURL)
    }

    @objc private func refreshFiles() {
        guard let currentFolderURL else { return }
        reloadFiles(from: currentFolderURL, rebuildSidebar: true)
    }

    @objc private func viewModeChanged() {
        settings.viewMode = FileViewMode.allCases[max(0, viewModeControl.selectedSegment)]
        store.saveSettings(settings)
        updateContentMode()
        refreshCollection()
    }

    @objc private func toggleSidebarFromToolbar() {
        toggleSidebarVisibility()
    }

    @objc private func openSettings() {
        AppLogger.info("openSettings")
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
        AppLogger.info("applyFilters requested all=\(allFiles.count)")
        let keyword = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let selectedKind = FileKind.allCases.first { $0.rawValue == typeButton.titleOfSelectedItem } ?? .all
        let selectedTime = timeButton.titleOfSelectedItem ?? "全部时间"
        let files = allFiles
        let settingsSnapshot = settings
        filterGeneration += 1
        let generation = filterGeneration

        filterQueue.async { [weak self] in
            AppLogger.info("applyFilters background start count=\(files.count)")
            let shown = Self.filteredAndSortedFiles(
                files,
                keyword: keyword,
                selectedKind: selectedKind,
                selectedTime: selectedTime,
                settings: settingsSnapshot
            )
            AppLogger.info("applyFilters background finished shown=\(shown.count)")

            DispatchQueue.main.async {
                guard let self, self.filterGeneration == generation else {
                    AppLogger.info("applyFilters result ignored")
                    return
                }
                self.shownFiles = shown
                self.refreshCollection()
            }
        }
    }

    private static func filteredAndSortedFiles(
        _ entries: [FileEntry],
        keyword: String,
        selectedKind: FileKind,
        selectedTime: String,
        settings: AppSettings
    ) -> [FileEntry] {
        sortedFiles(entries.filter { entry in
            let matchesKeyword = keyword.isEmpty || entry.name.localizedCaseInsensitiveContains(keyword)
            let matchesKind = selectedKind == .all || entry.kind == selectedKind
            let matchesTime = matchesTimeFilter(entry.modifiedAt, title: selectedTime)
            return matchesKeyword && matchesKind && matchesTime
        }, settings: settings)
    }

    private static func sortedFiles(_ entries: [FileEntry], settings: AppSettings) -> [FileEntry] {
        let pinnedPaths = Set(settings.pinnedFilePaths)
        return entries.sorted { left, right in
            let leftPinned = pinnedPaths.contains(left.url.path)
            let rightPinned = pinnedPaths.contains(right.url.path)
            if leftPinned != rightPinned {
                return leftPinned
            }
            if left.isDirectory != right.isDirectory {
                return left.isDirectory && !right.isDirectory
            }
            let isAscending: Bool
            switch settings.sortMode {
            case .name:
                isAscending = left.name.localizedStandardCompare(right.name) != .orderedDescending
            case .kind:
                let result = left.kind.rawValue.localizedStandardCompare(right.kind.rawValue)
                isAscending = result == .orderedSame
                    ? left.name.localizedStandardCompare(right.name) != .orderedDescending
                    : result == .orderedAscending
            case .dateModified:
                isAscending = (left.modifiedAt ?? .distantPast) < (right.modifiedAt ?? .distantPast)
            case .dateCreated:
                isAscending = (left.createdAt ?? .distantPast) < (right.createdAt ?? .distantPast)
            case .size:
                isAscending = (left.fileSize ?? 0) < (right.fileSize ?? 0)
            }
            return settings.sortAscending ? isAscending : !isAscending
        }
    }

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.panel.isVisible else { return event }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if self.isTextInputActive() {
                return event
            }
            if event.keyCode == 49 {
                self.togglePreviewSelected()
                return nil
            }
            if self.isPreviewPanelVisible(), [123, 124, 125, 126].contains(event.keyCode) {
                self.moveSelectionForPreview(keyCode: event.keyCode)
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

    private func installDragCancelMonitors() {
        let local = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown, .leftMouseUp]) { [weak self] event in
            if event.type == .rightMouseDown {
                guard let self, self.hasActiveDragInteraction() else { return event }
                self.cancelActiveDragInteractions()
                return nil
            }
            if event.type == .leftMouseUp {
                FolderQuickDragCancel.reset()
            }
            return event
        }

        dragCancelMonitors.append(local as Any)

        if let globalRight = NSEvent.addGlobalMonitorForEvents(matching: [.rightMouseDown], handler: { [weak self] _ in
            DispatchQueue.main.async {
                self?.cancelActiveDragInteractions()
            }
        }) {
            dragCancelMonitors.append(globalRight)
        }

        if let globalLeftUp = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp], handler: { _ in
            DispatchQueue.main.async {
                FolderQuickDragCancel.reset()
            }
        }) {
            dragCancelMonitors.append(globalLeftUp)
        }
    }

    private func selectedPreviewURL() -> URL? {
        guard let entry = primarySelectedEntry() else { return nil }
        return entry.isDirectory ? nil : entry.url
    }

    private func isTextInputActive() -> Bool {
        guard let responder = panel.firstResponder else { return false }
        if responder is NSTextView {
            return true
        }
        if let view = responder as? NSView,
           view.enclosingScrollView === scrollView || view.enclosingScrollView === listScrollView {
            return false
        }
        return false
    }

    private func isPreviewPanelVisible() -> Bool {
        QLPreviewPanel.sharedPreviewPanelExists() && (QLPreviewPanel.shared()?.isVisible == true)
    }

    private func closePreviewPanel() {
        guard QLPreviewPanel.sharedPreviewPanelExists(), let panel = QLPreviewPanel.shared() else { return }
        panel.orderOut(nil)
        self.panel.makeKeyAndOrderFront(nil)
    }

    private func togglePreviewSelected() {
        if isPreviewPanelVisible() {
            closePreviewPanel()
        } else {
            previewSelected()
        }
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
        panel.currentPreviewItemIndex = 0
    }

    private func moveSelectionForPreview(keyCode: UInt16) {
        if settings.viewMode == .list {
            moveListSelectionForPreview(keyCode: keyCode)
        } else {
            moveGridSelectionForPreview(keyCode: keyCode)
        }
    }

    private func moveListSelectionForPreview(keyCode: UInt16) {
        guard outlineView.numberOfRows > 0 else { return }
        let current = outlineView.selectedRow >= 0 ? outlineView.selectedRow : 0
        let next: Int

        switch keyCode {
        case 125:
            next = min(current + 1, outlineView.numberOfRows - 1)
        case 126:
            next = max(current - 1, 0)
        case 123:
            if outlineView.isItemExpanded(outlineView.item(atRow: current) as Any) {
                outlineView.collapseItem(outlineView.item(atRow: current))
            }
            return
        case 124:
            if let item = outlineView.item(atRow: current),
               outlineView.isExpandable(item),
               !outlineView.isItemExpanded(item) {
                outlineView.expandItem(item)
            }
            return
        default:
            return
        }

        outlineView.selectRowIndexes(IndexSet(integer: next), byExtendingSelection: false)
        outlineView.scrollRowToVisible(next)
    }

    private func moveGridSelectionForPreview(keyCode: UInt16) {
        guard !shownFiles.isEmpty else { return }
        let current = collectionView.selectionIndexPaths.first?.item ?? 0
        let next: Int

        switch keyCode {
        case 123:
            next = max(current - 1, 0)
        case 124:
            next = min(current + 1, shownFiles.count - 1)
        case 125:
            next = nearestGridItem(from: current, movingDown: true)
        case 126:
            next = nearestGridItem(from: current, movingDown: false)
        default:
            return
        }

        let indexPath = IndexPath(item: next, section: 0)
        collectionView.selectionIndexPaths = [indexPath]
        collectionView.scrollToItems(at: [indexPath], scrollPosition: [])
        previewButton.isEnabled = selectedPreviewURL() != nil
        updatePreviewPanelForSelectionChange()
    }

    private func nearestGridItem(from current: Int, movingDown: Bool) -> Int {
        guard let currentAttributes = collectionView.layoutAttributesForItem(at: IndexPath(item: current, section: 0)) else {
            return current
        }

        let currentCenter = NSPoint(x: currentAttributes.frame.midX, y: currentAttributes.frame.midY)
        var bestIndex = current
        var bestDistance = CGFloat.greatestFiniteMagnitude

        for index in shownFiles.indices where index != current {
            guard let attributes = collectionView.layoutAttributesForItem(at: IndexPath(item: index, section: 0)) else { continue }
            let center = NSPoint(x: attributes.frame.midX, y: attributes.frame.midY)
            let isCandidate = movingDown ? center.y > currentCenter.y + 1 : center.y < currentCenter.y - 1
            guard isCandidate else { continue }

            let verticalDistance = abs(center.y - currentCenter.y)
            let horizontalDistance = abs(center.x - currentCenter.x)
            let distance = verticalDistance * 1000 + horizontalDistance
            if distance < bestDistance {
                bestDistance = distance
                bestIndex = index
            }
        }

        return bestIndex
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

    private func pinnedMenuTitle() -> String {
        let urls = selectedURLs()
        guard !urls.isEmpty else { return "置顶文件" }
        let pinnedPaths = Set(settings.pinnedFilePaths)
        return urls.allSatisfy { pinnedPaths.contains($0.path) } ? "取消置顶" : "置顶文件"
    }

    @objc private func togglePinnedSelectedFiles() {
        let urls = selectedURLs()
        guard !urls.isEmpty else { return }
        var pinnedPaths = Set(settings.pinnedFilePaths)
        let shouldUnpin = urls.allSatisfy { pinnedPaths.contains($0.path) }
        for url in urls {
            if shouldUnpin {
                pinnedPaths.remove(url.path)
            } else {
                pinnedPaths.insert(url.path)
            }
        }
        settings.pinnedFilePaths = Array(pinnedPaths)
        store.saveSettings(settings)
        applyFilters()
    }

    @objc private func pasteFilesIntoCurrentFolder() {
        guard currentFolderURL != nil else { return }
        let pasteboard = NSPasteboard.general
        let items = FilePasteboardReader.fileURLs(from: pasteboard)
        guard !items.isEmpty else { return }
        _ = importFiles(items)
    }

    @discardableResult
    private func importFiles(_ urls: [URL], operation: FileImportOperation = .copy) -> Bool {
        importFiles(urls, to: currentFolderURL, operation: operation)
    }

    @discardableResult
    private func importFiles(_ urls: [URL], to folderURL: URL?, operation: FileImportOperation = .copy) -> Bool {
        guard let folderURL else { return false }
        let tasks = urls.compactMap { source -> FileImportTask? in
            guard source.deletingLastPathComponent() != folderURL else { return nil }
            guard let destination = resolvedImportDestination(for: source, in: folderURL) else { return nil }
            return FileImportTask(source: source, destination: destination, operation: operation)
        }

        guard !tasks.isEmpty else { return false }
        startImportTasks(tasks, targetFolderURL: folderURL, operation: operation)
        return true
    }

    private func startImportTasks(_ tasks: [FileImportTask], targetFolderURL: URL, operation: FileImportOperation) {
        let title = operation == .move ? "正在移动" : "正在复制"
        transferProgressPanel.show(
            on: panel.screen ?? screenContainingMouse(),
            title: title,
            detail: tasks.count == 1 ? tasks[0].source.lastPathComponent : "\(tasks.count) 个项目"
        )

        transferQueue.async { [weak self] in
            guard let self else { return }
            do {
                let totalBytes = tasks.reduce(UInt64(0)) { partial, task in
                    partial + self.transferSize(of: task.source)
                }
                var completedBytes: UInt64 = 0

                for task in tasks {
                    DispatchQueue.main.async {
                        self.transferProgressPanel.update(
                            title: title,
                            detail: task.source.lastPathComponent,
                            completed: completedBytes,
                            total: totalBytes
                        )
                    }

                    switch task.operation {
                    case .copy:
                        try self.copyItemWithProgress(
                            from: task.source,
                            to: task.destination,
                            completedBytes: &completedBytes,
                            totalBytes: totalBytes,
                            title: title
                        )
                    case .move:
                        let size = self.transferSize(of: task.source)
                        try FileManager.default.moveItem(at: task.source, to: task.destination)
                        completedBytes += size
                        DispatchQueue.main.async {
                            self.transferProgressPanel.update(
                                title: title,
                                detail: task.source.lastPathComponent,
                                completed: completedBytes,
                                total: totalBytes
                            )
                        }
                    }
                }

                DispatchQueue.main.async {
                    self.transferProgressPanel.finish(title: "完成", detail: "\(tasks.count) 个项目已处理")
                    if targetFolderURL == self.currentFolderURL || operation == .move {
                        self.refreshFiles()
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.transferProgressPanel.finish(title: operation == .move ? "移动失败" : "复制失败", detail: error.localizedDescription)
                    self.showAlert(title: operation == .move ? "移动失败" : "复制失败", message: error.localizedDescription)
                    if targetFolderURL == self.currentFolderURL || operation == .move {
                        self.refreshFiles()
                    }
                }
            }
        }
    }

    private func transferSize(of url: URL) -> UInt64 {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .fileSizeKey, .totalFileAllocatedSizeKey]
        guard let values = try? url.resourceValues(forKeys: keys) else { return 0 }
        if values.isDirectory == true {
            guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles]) else {
                return 0
            }
            return enumerator.compactMap { item -> UInt64? in
                guard let fileURL = item as? URL,
                      let itemValues = try? fileURL.resourceValues(forKeys: keys),
                      itemValues.isDirectory != true else { return nil }
                return UInt64(itemValues.totalFileAllocatedSize ?? itemValues.fileSize ?? 0)
            }.reduce(0, +)
        }
        return UInt64(values.totalFileAllocatedSize ?? values.fileSize ?? 0)
    }

    private func copyItemWithProgress(
        from source: URL,
        to destination: URL,
        completedBytes: inout UInt64,
        totalBytes: UInt64,
        title: String
    ) throws {
        let values = try source.resourceValues(forKeys: [.isDirectoryKey])
        if values.isDirectory == true {
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            guard let enumerator = FileManager.default.enumerator(
                at: source,
                includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
                options: []
            ) else { return }

            for case let itemURL as URL in enumerator {
                let relativePath = String(itemURL.path.dropFirst(source.path.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                guard !relativePath.isEmpty else { continue }
                let itemDestination = destination.appendingPathComponent(relativePath)
                let itemValues = try itemURL.resourceValues(forKeys: [.isDirectoryKey])
                if itemValues.isDirectory == true {
                    try FileManager.default.createDirectory(at: itemDestination, withIntermediateDirectories: true)
                } else {
                    try copyFileWithProgress(
                        from: itemURL,
                        to: itemDestination,
                        completedBytes: &completedBytes,
                        totalBytes: totalBytes,
                        title: title
                    )
                }
            }
            return
        }

        try copyFileWithProgress(
            from: source,
            to: destination,
            completedBytes: &completedBytes,
            totalBytes: totalBytes,
            title: title
        )
    }

    private func copyFileWithProgress(
        from source: URL,
        to destination: URL,
        completedBytes: inout UInt64,
        totalBytes: UInt64,
        title: String
    ) throws {
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        FileManager.default.createFile(atPath: destination.path, contents: nil)

        let input = try FileHandle(forReadingFrom: source)
        defer { try? input.close() }

        let output = try FileHandle(forWritingTo: destination)
        defer { try? output.close() }

        let chunkSize = 1024 * 1024
        var lastUpdate = Date(timeIntervalSince1970: 0)

        while autoreleasepool(invoking: {
            let data = input.readData(ofLength: chunkSize)
            guard !data.isEmpty else { return false }
            output.write(data)
            completedBytes += UInt64(data.count)

            let now = Date()
            if now.timeIntervalSince(lastUpdate) > 0.08 {
                lastUpdate = now
                let currentCompleted = completedBytes
                DispatchQueue.main.async {
                    self.transferProgressPanel.update(
                        title: title,
                        detail: source.lastPathComponent,
                        completed: currentCompleted,
                        total: totalBytes
                    )
                }
            }
            return true
        }) {}
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
        settings.pinnedFilePaths.removeAll { path in urls.contains(URL(fileURLWithPath: path)) }
        store.saveSettings(settings)
        refreshFiles()
    }

    @objc private func renameSelectedFile() {
        guard let entry = primarySelectedEntry() else { return }

        if settings.viewMode == .grid,
           let index = shownFiles.firstIndex(where: { $0.url == entry.url }),
           let item = collectionView.item(at: IndexPath(item: index, section: 0)) as? FileItemView {
            item.beginRenaming()
            return
        }

        if settings.viewMode == .list,
           let row = selectedListRows().first,
           let view = outlineView.view(atColumn: 0, row: row, makeIfNecessary: false) as? FileListRowView {
            view.beginRenaming()
        }
    }

    private func startRename(url: URL, newName: String) {
        let trimmedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, trimmedName != url.lastPathComponent else { return }
        let destination = url.deletingLastPathComponent().appendingPathComponent(trimmedName)
        do {
            try FileManager.default.moveItem(at: url, to: destination)
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

        let pin = NSMenuItem(title: pinnedMenuTitle(), action: #selector(togglePinnedSelectedFiles), keyEquivalent: "")
        pin.target = self
        menu.addItem(pin)

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

    private func emptyAreaMenu() -> NSMenu {
        let menu = NSMenu()

        let newFolder = NSMenuItem(title: "新建文件夹", action: #selector(createFolderInCurrentDirectory), keyEquivalent: "")
        newFolder.target = self
        menu.addItem(newFolder)

        let reveal = NSMenuItem(title: "在访达中显示", action: #selector(revealCurrentFolderInFinder), keyEquivalent: "")
        reveal.target = self
        menu.addItem(reveal)

        let sortItem = NSMenuItem(title: "排列方式", action: nil, keyEquivalent: "")
        let sortMenu = NSMenu()
        for mode in FileSortMode.allCases {
            let item = NSMenuItem(title: mode.rawValue, action: #selector(sortModeMenuItem(_:)), keyEquivalent: "")
            item.representedObject = mode.rawValue
            item.state = settings.sortMode == mode ? .on : .off
            item.target = self
            sortMenu.addItem(item)
        }
        sortItem.submenu = sortMenu
        menu.addItem(sortItem)

        let timeItem = NSMenuItem(title: "时间筛选", action: nil, keyEquivalent: "")
        let timeMenu = NSMenu()
        for title in ["全部时间", "今天", "昨天", "最近 7 天", "最近 30 天"] {
            let item = NSMenuItem(title: title, action: #selector(timeFilterMenuItem(_:)), keyEquivalent: "")
            item.representedObject = title
            item.state = timeButton.titleOfSelectedItem == title ? .on : .off
            item.target = self
            timeMenu.addItem(item)
        }
        timeItem.submenu = timeMenu
        menu.addItem(timeItem)

        let kindItem = NSMenuItem(title: "文件筛选", action: nil, keyEquivalent: "")
        let kindMenu = NSMenu()
        for kind in FileKind.allCases {
            let item = NSMenuItem(title: kind.rawValue, action: #selector(kindFilterMenuItem(_:)), keyEquivalent: "")
            item.representedObject = kind.rawValue
            item.state = typeButton.titleOfSelectedItem == kind.rawValue ? .on : .off
            item.target = self
            kindMenu.addItem(item)
        }
        kindItem.submenu = kindMenu
        menu.addItem(kindItem)

        let viewItem = NSMenuItem(title: "视图模式", action: nil, keyEquivalent: "")
        let viewMenu = NSMenu()
        for mode in FileViewMode.allCases {
            let item = NSMenuItem(title: mode.rawValue, action: #selector(viewModeMenuItem(_:)), keyEquivalent: "")
            item.representedObject = mode.rawValue
            item.state = settings.viewMode == mode ? .on : .off
            item.target = self
            viewMenu.addItem(item)
        }
        viewItem.submenu = viewMenu
        menu.addItem(viewItem)

        let sidebar = NSMenuItem(title: "显示侧栏", action: #selector(toggleSidebarFromMenu), keyEquivalent: "")
        sidebar.state = settings.showSidebar ? .on : .off
        sidebar.target = self
        menu.addItem(sidebar)

        menu.addItem(NSMenuItem.separator())

        let settingsItem = NSMenuItem(title: "设置", action: #selector(openSettings), keyEquivalent: "")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let terminal = NSMenuItem(title: "进入终端", action: #selector(openTerminalHere), keyEquivalent: "")
        terminal.target = self
        menu.addItem(terminal)

        return menu
    }

    @objc private func createFolderInCurrentDirectory() {
        guard let currentFolderURL else { return }
        let destination = uniqueDestination(for: "未命名文件夹", in: currentFolderURL)
        do {
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
            refreshFiles()
        } catch {
            showAlert(title: "新建文件夹失败", message: error.localizedDescription)
        }
    }

    @objc private func revealCurrentFolderInFinder() {
        guard let currentFolderURL else { return }
        NSWorkspace.shared.open(currentFolderURL)
    }

    @objc private func sortModeMenuItem(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let mode = FileSortMode(rawValue: rawValue) else { return }
        setSortMode(mode, toggleIfSame: false)
    }

    private func setSortMode(_ mode: FileSortMode, toggleIfSame: Bool) {
        if settings.sortMode == mode, toggleIfSame {
            settings.sortAscending.toggle()
        } else {
            settings.sortMode = mode
            settings.sortAscending = defaultSortAscending(for: mode)
        }
        store.saveSettings(settings)
        updateListColumnTitles()
        applyFilters()
    }

    private func defaultSortAscending(for mode: FileSortMode) -> Bool {
        switch mode {
        case .name, .kind:
            return true
        case .dateModified, .dateCreated, .size:
            return false
        }
    }

    @objc private func viewModeMenuItem(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let mode = FileViewMode(rawValue: rawValue) else { return }
        settings.viewMode = mode
        store.saveSettings(settings)
        updateContentMode()
        refreshCollection()
    }

    @objc private func toggleSidebarFromMenu() {
        toggleSidebarVisibility()
    }

    private func toggleSidebarVisibility() {
        settings.showSidebar.toggle()
        store.saveSettings(settings)
        updateContentMode()
    }

    private func updateSidebarButtonState() {
        sidebarButton.contentTintColor = settings.showSidebar ? .controlAccentColor : nil
    }

    @objc private func timeFilterMenuItem(_ sender: NSMenuItem) {
        guard let title = sender.representedObject as? String,
              let item = timeButton.item(withTitle: title) else { return }
        timeButton.select(item)
        applyFilters()
    }

    @objc private func kindFilterMenuItem(_ sender: NSMenuItem) {
        guard let title = sender.representedObject as? String,
              let item = typeButton.item(withTitle: title) else { return }
        typeButton.select(item)
        applyFilters()
    }

    @objc private func openTerminalHere() {
        guard let currentFolderURL else { return }
        let terminalURL = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
        NSWorkspace.shared.open([currentFolderURL], withApplicationAt: terminalURL, configuration: NSWorkspace.OpenConfiguration())
    }

    private func applySettings(_ newSettings: AppSettings) {
        AppLogger.info("applySettings start")
        let oldSettings = settings
        settings = newSettings
        store.saveSettings(settings)
        panel.alphaValue = settings.opacity

        var needsVisibleRefresh = false
        if oldSettings.iconSize != settings.iconSize || oldSettings.iconSpacing != settings.iconSpacing {
            applyItemSize()
            needsVisibleRefresh = true
        }
        if oldSettings.listInfoColumns != settings.listInfoColumns {
            configureListColumns()
            needsVisibleRefresh = true
        } else {
            updateListColumnTitles()
        }
        if oldSettings.viewMode != settings.viewMode || oldSettings.showSidebar != settings.showSidebar {
            updateContentMode()
            needsVisibleRefresh = true
        } else {
            updateSidebarButtonState()
        }
        if oldSettings.showBottomPath != settings.showBottomPath {
            updatePathLabel()
        }
        if oldSettings.edgeTriggerEnabled != settings.edgeTriggerEnabled ||
            oldSettings.triggerPositions != settings.triggerPositions {
            rebuildEdgeTriggers()
        } else if oldSettings.showEdgeTrigger != settings.showEdgeTrigger {
            edgePanels.forEach { $0.backgroundColor = settings.showEdgeTrigger ? NSColor.controlAccentColor.withAlphaComponent(0.18) : .clear }
        }
        if oldSettings.sidebarPosition != settings.sidebarPosition {
            positionPanel(anchor: settings.sidebarPosition, screen: screenContainingMouse() ?? NSScreen.main)
        }
        if oldSettings.sortMode != settings.sortMode ||
            oldSettings.sortAscending != settings.sortAscending {
            applyFilters()
        } else if needsVisibleRefresh {
            refreshCollection()
        }
        AppLogger.info("applySettings finished")
    }

    private static func matchesTimeFilter(_ date: Date?, title: String) -> Bool {
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
        AppLogger.error("showAlert title=\(title) message=\(message)")
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
        applySidebarWidth()
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
            fileItem.onRenameCommit = { [weak self] url, newName in
                self?.startRename(url: url, newName: newName)
            }
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
        if outlineView === sidebarOutlineView {
            guard let node = item as? FileNode else {
                return sidebarRootNodes.count
            }
            return loadSidebarChildren(for: node).count
        }
        guard let node = item as? FileNode else {
            return listRootNodes.count
        }
        return loadChildren(for: node).count
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if outlineView === sidebarOutlineView {
            guard let node = item as? FileNode else {
                return sidebarRootNodes[index]
            }
            return loadSidebarChildren(for: node)[index]
        }
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
        if outlineView === sidebarOutlineView {
            let view = outlineView.makeView(withIdentifier: SidebarFolderRowView.identifier, owner: self) as? SidebarFolderRowView ?? SidebarFolderRowView()
            view.identifier = SidebarFolderRowView.identifier
            view.configure(entry: node.entry)
            return view
        }

        guard tableColumn?.identifier.rawValue == "name" else {
            let view = outlineView.makeView(withIdentifier: FileInfoCellView.identifier, owner: self) as? FileInfoCellView ?? FileInfoCellView()
            view.identifier = FileInfoCellView.identifier
            if let rawValue = tableColumn?.identifier.rawValue,
               let column = ListInfoColumn(rawValue: rawValue) {
                view.configure(text: listInfoText(for: node.entry, column: column))
            }
            return view
        }

        let view = outlineView.makeView(withIdentifier: FileListRowView.identifier, owner: self) as? FileListRowView ?? FileListRowView()
        view.identifier = FileListRowView.identifier
        view.configure(entry: node.entry, depth: outlineView.level(forItem: item))
        view.onRenameCommit = { [weak self] url, newName in
            self?.startRename(url: url, newName: newName)
        }
        return view
    }

    func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> NSPasteboardWriting? {
        guard outlineView !== sidebarOutlineView else { return nil }
        guard let node = item as? FileNode else { return nil }
        return node.entry.url as NSURL
    }

    func outlineView(_ outlineView: NSOutlineView, didClick tableColumn: NSTableColumn) {
        guard outlineView === self.outlineView else { return }
        guard let mode = sortMode(for: tableColumn) else { return }
        setSortMode(mode, toggleIfSame: true)
    }

    private func sortMode(for tableColumn: NSTableColumn) -> FileSortMode? {
        let identifier = tableColumn.identifier.rawValue
        if identifier == "name" { return .name }
        guard let column = ListInfoColumn(rawValue: identifier) else { return nil }
        return sortMode(for: column)
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        if notification.object as AnyObject? === sidebarOutlineView {
            let row = sidebarOutlineView.selectedRow
            guard row >= 0, let node = sidebarOutlineView.item(atRow: row) as? FileNode else { return }
            enterFolderFromSidebar(node.entry.url)
            return
        }

        guard notification.object as AnyObject? === outlineView else { return }
        previewButton.isEnabled = selectedPreviewURL() != nil
        updateLevelDots()
        updatePreviewPanelForSelectionChange()
    }

    func outlineViewItemDidExpand(_ notification: Notification) {
        guard notification.object as AnyObject? === outlineView else { return }
        guard let node = notification.userInfo?["NSObject"] as? FileNode else { return }
        setListNode(node, expanded: true)
        updateLevelDots()
    }

    func outlineViewItemDidCollapse(_ notification: Notification) {
        guard notification.object as AnyObject? === outlineView else { return }
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

    @objc private func sidebarDoubleClicked() {
        let row = sidebarOutlineView.clickedRow >= 0 ? sidebarOutlineView.clickedRow : sidebarOutlineView.selectedRow
        guard row >= 0, let node = sidebarOutlineView.item(atRow: row) as? FileNode else { return }
        enterFolderFromSidebar(node.entry.url)
    }

    private func enterFolderFromSidebar(_ url: URL) {
        guard let selectedRootURL else { return }
        currentFolderURL = url
        navigationStack = parentPathURLs(from: selectedRootURL, to: url)
        saveCurrentFolderState()
        reloadFiles(from: url)
    }

    private func parentPathURLs(from root: URL, to target: URL) -> [URL] {
        guard target.path.hasPrefix(root.path), target != root else { return [] }
        var urls: [URL] = []
        var current = target.deletingLastPathComponent()
        while current.path.hasPrefix(root.path), current != root {
            urls.insert(current, at: 0)
            current.deleteLastPathComponent()
        }
        urls.insert(root, at: 0)
        return urls
    }

    private func listInfoText(for entry: FileEntry, column: ListInfoColumn) -> String {
        switch column {
        case .kind:
            return entry.isDirectory ? "文件夹" : entry.kind.rawValue
        case .dateModified:
            return formattedDate(entry.modifiedAt)
        case .dateCreated:
            return formattedDate(entry.createdAt)
        case .size:
            guard !entry.isDirectory, let fileSize = entry.fileSize else { return "--" }
            return ByteCountFormatter.string(fromByteCount: Int64(fileSize), countStyle: .file)
        }
    }

    private func formattedDate(_ date: Date?) -> String {
        guard let date else { return "--" }
        return DateFormatter.localizedString(from: date, dateStyle: .short, timeStyle: .short)
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

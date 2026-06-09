import AppKit

final class FileCollectionView: NSCollectionView {
    var menuProvider: (() -> NSMenu?)?
    var emptyMenuProvider: (() -> NSMenu?)?
    var onDoubleClickItem: ((IndexPath) -> Void)?
    var onDropFiles: (([URL], IndexPath?, FileImportOperation) -> Bool)?
    var onHoverItem: ((IndexPath?) -> Void)?
    var onEmptyClick: (() -> Void)?
    var dragURLsProvider: (() -> [URL])?
    var isDropTargetProvider: ((IndexPath) -> Bool)?
    private var lastClickedIndexPath: IndexPath?
    private var mouseDownIndexPath: IndexPath?
    private var mouseDownPoint: NSPoint?
    private var pendingSingleSelectionIndexPath: IndexPath?
    private var didStartManualDrag = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes(FilePasteboardReader.supportedTypes)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForDraggedTypes(FilePasteboardReader.supportedTypes)
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let indexPath = finderLikeIndexPath(at: point) else {
            selectionIndexPaths = []
            lastClickedIndexPath = nil
            mouseDownIndexPath = nil
            mouseDownPoint = nil
            pendingSingleSelectionIndexPath = nil
            didStartManualDrag = false
            onEmptyClick?()
            super.mouseDown(with: event)
            return
        }

        mouseDownIndexPath = indexPath
        mouseDownPoint = point
        pendingSingleSelectionIndexPath = nil
        didStartManualDrag = false

        if event.clickCount == 2 {
            updateSelection(for: indexPath, event: event)
            onDoubleClickItem?(indexPath)
            return
        }

        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let shouldKeepMultiSelectionForDrag =
            selectionIndexPaths.count > 1 &&
            selectionIndexPaths.contains(indexPath) &&
            !modifiers.contains(.command) &&
            !modifiers.contains(.shift)

        if shouldKeepMultiSelectionForDrag {
            pendingSingleSelectionIndexPath = indexPath
            return
        }

        updateSelection(for: indexPath, event: event)

        if indexPathForItem(at: point) != nil {
            super.mouseDown(with: event)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard !didStartManualDrag,
              mouseDownIndexPath != nil,
              let mouseDownPoint else {
            super.mouseDragged(with: event)
            return
        }

        let point = convert(event.locationInWindow, from: nil)
        let distance = hypot(point.x - mouseDownPoint.x, point.y - mouseDownPoint.y)
        guard distance >= 3 else { return }

        let urls = dragURLsProvider?() ?? []
        guard !urls.isEmpty else {
            super.mouseDragged(with: event)
            return
        }

        didStartManualDrag = true
        let items = urls.map { url -> NSDraggingItem in
            let item = NSDraggingItem(pasteboardWriter: url as NSURL)
            item.setDraggingFrame(NSRect(x: point.x - 24, y: point.y - 24, width: 48, height: 48), contents: NSWorkspace.shared.icon(forFile: url.path))
            return item
        }
        beginDraggingSession(with: items, event: event, source: self)
    }

    override func mouseUp(with event: NSEvent) {
        mouseDownIndexPath = nil
        mouseDownPoint = nil
        if !didStartManualDrag, let pendingSingleSelectionIndexPath {
            selectionIndexPaths = [pendingSingleSelectionIndexPath]
            lastClickedIndexPath = pendingSingleSelectionIndexPath
        }
        pendingSingleSelectionIndexPath = nil
        didStartManualDrag = false
        super.mouseUp(with: event)
    }

    override func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        [.copy, .move]
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        guard let indexPath = finderLikeIndexPath(at: point) else {
            selectionIndexPaths = []
            lastClickedIndexPath = nil
            return emptyMenuProvider?()
        }
        if !selectionIndexPaths.contains(indexPath) {
            selectionIndexPaths = [indexPath]
            lastClickedIndexPath = indexPath
        }
        return menuProvider?()
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard !FolderQuickDragCancel.isCancelled else { return [] }
        return dragOperation(for: sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard !FolderQuickDragCancel.isCancelled else {
            onHoverItem?(nil)
            return []
        }
        onHoverItem?(dropIndexPath(for: sender))
        return dragOperation(for: sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard !FolderQuickDragCancel.isCancelled else {
            onHoverItem?(nil)
            FolderQuickDragCancel.reset()
            return false
        }
        let urls = FilePasteboardReader.fileURLs(from: sender.draggingPasteboard)
        guard !urls.isEmpty else { return false }
        let indexPath = dropIndexPath(for: sender)
        onHoverItem?(nil)
        return onDropFiles?(urls, indexPath, FileImportOperation.current()) ?? false
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        onHoverItem?(nil)
        FolderQuickDragCancel.reset()
    }

    private func dragOperation(for sender: NSDraggingInfo) -> NSDragOperation {
        FilePasteboardReader.fileURLs(from: sender.draggingPasteboard).isEmpty ? [] : FileImportOperation.current().dragOperation
    }

    private func dropIndexPath(for sender: NSDraggingInfo) -> IndexPath? {
        let convertedPoint = convert(sender.draggingLocation, from: nil)
        return dropFriendlyIndexPath(at: sender.draggingLocation)
            ?? dropFriendlyIndexPath(at: convertedPoint)
    }

    private func dropFriendlyIndexPath(at point: NSPoint) -> IndexPath? {
        guard let layoutAttributes = collectionViewLayout?.layoutAttributesForElements(in: visibleRect) else {
            return nil
        }

        let candidates = layoutAttributes
            .filter { $0.representedElementCategory == .item }
            .compactMap { attributes -> (IndexPath, NSRect, CGFloat)? in
                guard let indexPath = attributes.indexPath else { return nil }
                if isDropTargetProvider?(indexPath) == false { return nil }
                let frame = attributes.frame.insetBy(dx: -14, dy: -34)
                guard frame.contains(point) else { return nil }
                let distance = hypot(point.x - attributes.frame.midX, point.y - attributes.frame.midY)
                return (indexPath, frame, distance)
            }

        return candidates
            .sorted {
                if abs($0.2 - $1.2) > 0.5 { return $0.2 < $1.2 }
                return $0.1.minY == $1.1.minY ? $0.1.minX < $1.1.minX : $0.1.minY > $1.1.minY
            }
            .first?
            .0
    }

    private func finderLikeIndexPath(at point: NSPoint) -> IndexPath? {
        if let indexPath = indexPathForItem(at: point) {
            return indexPath
        }

        guard let layoutAttributes = collectionViewLayout?.layoutAttributesForElements(in: visibleRect) else {
            return nil
        }

        return layoutAttributes
            .filter { $0.representedElementCategory == .item && $0.frame.contains(point) }
            .sorted { $0.frame.minY == $1.frame.minY ? $0.frame.minX < $1.frame.minX : $0.frame.minY > $1.frame.minY }
            .first?
            .indexPath
    }

    private func updateSelection(for indexPath: IndexPath, event: NSEvent) {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        if modifiers.contains(.command) {
            if selectionIndexPaths.contains(indexPath) {
                selectionIndexPaths.remove(indexPath)
            } else {
                selectionIndexPaths.insert(indexPath)
            }
            lastClickedIndexPath = indexPath
            return
        }

        if modifiers.contains(.shift),
           let lastClickedIndexPath,
           lastClickedIndexPath.section == indexPath.section {
            let bounds = min(lastClickedIndexPath.item, indexPath.item)...max(lastClickedIndexPath.item, indexPath.item)
            selectionIndexPaths = Set(bounds.map { IndexPath(item: $0, section: indexPath.section) })
            return
        }

        selectionIndexPaths = [indexPath]
        lastClickedIndexPath = indexPath
    }
}

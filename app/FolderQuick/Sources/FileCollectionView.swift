import AppKit

final class FileCollectionView: NSCollectionView {
    var menuProvider: (() -> NSMenu?)?
    var onDoubleClickItem: ((IndexPath) -> Void)?
    var onDropFiles: (([URL], IndexPath?) -> Bool)?
    var onHoverItem: ((IndexPath?) -> Void)?
    var onEmptyClick: (() -> Void)?
    private var lastClickedIndexPath: IndexPath?

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
            onEmptyClick?()
            super.mouseDown(with: event)
            return
        }

        updateSelection(for: indexPath, event: event)

        if event.clickCount == 2 {
            onDoubleClickItem?(indexPath)
            return
        }

        if indexPathForItem(at: point) != nil {
            super.mouseDown(with: event)
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        if let indexPath = finderLikeIndexPath(at: point), !selectionIndexPaths.contains(indexPath) {
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
        return onDropFiles?(urls, indexPath) ?? false
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        onHoverItem?(nil)
        FolderQuickDragCancel.reset()
    }

    private func dragOperation(for sender: NSDraggingInfo) -> NSDragOperation {
        FilePasteboardReader.fileURLs(from: sender.draggingPasteboard).isEmpty ? [] : .copy
    }

    private func dropIndexPath(for sender: NSDraggingInfo) -> IndexPath? {
        let point = convert(sender.draggingLocation, from: nil)
        return finderLikeIndexPath(at: point)
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

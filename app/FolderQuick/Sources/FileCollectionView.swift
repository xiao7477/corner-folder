import AppKit

final class FileCollectionView: NSCollectionView {
    var menuProvider: (() -> NSMenu?)?
    var onDoubleClickItem: ((IndexPath) -> Void)?
    var onDropFiles: (([URL], IndexPath?) -> Bool)?
    var onHoverItem: ((IndexPath?) -> Void)?

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
        if event.clickCount == 2, let indexPath = indexPathForItem(at: point) {
            onDoubleClickItem?(indexPath)
            return
        }
        super.mouseDown(with: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        if let indexPath = indexPathForItem(at: point), !selectionIndexPaths.contains(indexPath) {
            selectionIndexPaths = [indexPath]
        }
        return menuProvider?()
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        return dragOperation(for: sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        onHoverItem?(dropIndexPath(for: sender))
        return dragOperation(for: sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = FilePasteboardReader.fileURLs(from: sender.draggingPasteboard)
        guard !urls.isEmpty else { return false }
        let indexPath = dropIndexPath(for: sender)
        onHoverItem?(nil)
        return onDropFiles?(urls, indexPath) ?? false
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        onHoverItem?(nil)
    }

    private func dragOperation(for sender: NSDraggingInfo) -> NSDragOperation {
        FilePasteboardReader.fileURLs(from: sender.draggingPasteboard).isEmpty ? [] : .copy
    }

    private func dropIndexPath(for sender: NSDraggingInfo) -> IndexPath? {
        let point = convert(sender.draggingLocation, from: nil)
        return indexPathForItem(at: point)
    }
}

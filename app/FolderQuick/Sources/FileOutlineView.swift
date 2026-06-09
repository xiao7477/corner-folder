import AppKit

final class FolderQuickTableHeaderView: NSTableHeaderView {
    var menuProvider: (() -> NSMenu?)?

    override func menu(for event: NSEvent) -> NSMenu? {
        menuProvider?()
    }
}

final class FileOutlineView: NSOutlineView {
    var menuProvider: (() -> NSMenu?)?
    var emptyMenuProvider: (() -> NSMenu?)?
    var onDropFiles: (([URL], Int?, FileImportOperation) -> Bool)?
    var onHoverRow: ((Int?) -> Void)?
    var onEmptyClick: (() -> Void)?

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
        if row(at: point) < 0 {
            deselectAll(nil)
            onEmptyClick?()
        }
        super.mouseDown(with: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        let row = row(at: point)
        guard row >= 0 else {
            deselectAll(nil)
            return emptyMenuProvider?()
        }
        if !selectedRowIndexes.contains(row) {
            selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }
        return menuProvider?()
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard !FolderQuickDragCancel.isCancelled else { return [] }
        return dragOperation(for: sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard !FolderQuickDragCancel.isCancelled else {
            onHoverRow?(nil)
            return []
        }
        onHoverRow?(dropRow(for: sender))
        return dragOperation(for: sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard !FolderQuickDragCancel.isCancelled else {
            onHoverRow?(nil)
            FolderQuickDragCancel.reset()
            return false
        }
        let urls = FilePasteboardReader.fileURLs(from: sender.draggingPasteboard)
        guard !urls.isEmpty else { return false }
        let row = dropRow(for: sender)
        onHoverRow?(nil)
        return onDropFiles?(urls, row, FileImportOperation.current()) ?? false
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        onHoverRow?(nil)
        FolderQuickDragCancel.reset()
    }

    private func dragOperation(for sender: NSDraggingInfo) -> NSDragOperation {
        FilePasteboardReader.fileURLs(from: sender.draggingPasteboard).isEmpty ? [] : FileImportOperation.current().dragOperation
    }

    private func dropRow(for sender: NSDraggingInfo) -> Int? {
        let point = convert(sender.draggingLocation, from: nil)
        let row = row(at: point)
        return row >= 0 ? row : nil
    }
}

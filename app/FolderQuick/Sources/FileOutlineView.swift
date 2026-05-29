import AppKit

final class FileOutlineView: NSOutlineView {
    var menuProvider: (() -> NSMenu?)?
    var onDropFiles: (([URL], Int?) -> Bool)?
    var onHoverRow: ((Int?) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes(FilePasteboardReader.supportedTypes)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForDraggedTypes(FilePasteboardReader.supportedTypes)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        let row = row(at: point)
        if row >= 0, !selectedRowIndexes.contains(row) {
            selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }
        return menuProvider?()
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        return dragOperation(for: sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        onHoverRow?(dropRow(for: sender))
        return dragOperation(for: sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = FilePasteboardReader.fileURLs(from: sender.draggingPasteboard)
        guard !urls.isEmpty else { return false }
        let row = dropRow(for: sender)
        onHoverRow?(nil)
        return onDropFiles?(urls, row) ?? false
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        onHoverRow?(nil)
    }

    private func dragOperation(for sender: NSDraggingInfo) -> NSDragOperation {
        FilePasteboardReader.fileURLs(from: sender.draggingPasteboard).isEmpty ? [] : .copy
    }

    private func dropRow(for sender: NSDraggingInfo) -> Int? {
        let point = convert(sender.draggingLocation, from: nil)
        let row = row(at: point)
        return row >= 0 ? row : nil
    }
}

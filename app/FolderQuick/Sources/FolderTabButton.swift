import AppKit
import QuartzCore

final class FolderTabButton: NSView, NSDraggingSource {
    static let pasteboardType = NSPasteboard.PasteboardType("local.folderquick.folder-tab")

    var folderIndex: Int = 0
    var title: String = "" {
        didSet { needsDisplay = true }
    }
    var isSelected: Bool = false {
        didSet { needsDisplay = true }
    }
    var isMoveModeEnabled: Bool = false {
        didSet { updateJiggle() }
    }
    var onClick: ((Int) -> Void)?
    var menuProvider: ((Int) -> NSMenu?)?

    override var acceptsFirstResponder: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8)
        let fill = isSelected ? NSColor.controlAccentColor.withAlphaComponent(0.28) : NSColor.controlBackgroundColor.withAlphaComponent(0.52)
        fill.setFill()
        path.fill()

        if isSelected {
            NSColor.controlAccentColor.withAlphaComponent(0.7).setStroke()
            path.lineWidth = 1
            path.stroke()
        }

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byTruncatingMiddle
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: isSelected ? .semibold : .medium),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph
        ]
        let textRect = rect.insetBy(dx: 12, dy: 7)
        title.draw(in: textRect, withAttributes: attributes)
    }

    override func mouseDown(with event: NSEvent) {
        if event.type == .rightMouseDown {
            return
        }
        guard !isMoveModeEnabled else { return }
        onClick?(folderIndex)
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let menu = menuProvider?(folderIndex) else { return }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    override func mouseDragged(with event: NSEvent) {
        guard isMoveModeEnabled else { return }
        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setString("\(folderIndex)", forType: Self.pasteboardType)
        let item = NSDraggingItem(pasteboardWriter: pasteboardItem)
        item.draggingFrame = bounds
        item.imageComponentsProvider = { [weak self] in
            guard let self else { return [] }
            let component = NSDraggingImageComponent(key: .icon)
            component.contents = self.snapshot()
            component.frame = self.bounds
            return [component]
        }
        beginDraggingSession(with: [item], event: event, source: self)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .move
    }

    private func snapshot() -> NSImage {
        guard let representation = bitmapImageRepForCachingDisplay(in: bounds) else {
            return NSImage(size: bounds.size)
        }
        cacheDisplay(in: bounds, to: representation)
        let image = NSImage(size: bounds.size)
        image.addRepresentation(representation)
        return image
    }

    private func updateJiggle() {
        guard isMoveModeEnabled else {
            layer?.removeAnimation(forKey: "folderquick-jiggle")
            layer?.setAffineTransform(.identity)
            return
        }

        let animation = CAKeyframeAnimation(keyPath: "transform.rotation.z")
        animation.values = [-0.018, 0.018, -0.012, 0.012]
        animation.duration = 0.22
        animation.repeatCount = .infinity
        animation.autoreverses = true
        animation.isRemovedOnCompletion = false
        layer?.add(animation, forKey: "folderquick-jiggle")
    }
}

final class TabBarView: NSView {
    var onDropTab: ((Int, Int) -> Void)?
    override var mouseDownCanMoveWindow: Bool { false }
    private var insertionLineX: CGFloat? {
        didSet { needsDisplay = true }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([FolderTabButton.pasteboardType])
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForDraggedTypes([FolderTabButton.pasteboardType])
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        updateInsertionLine(sender)
        return .move
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        updateInsertionLine(sender)
        return .move
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        insertionLineX = nil
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let text = sender.draggingPasteboard.string(forType: FolderTabButton.pasteboardType),
              let from = Int(text) else {
            return false
        }

        let point = convert(sender.draggingLocation, from: nil)
        guard let target = insertionTarget(at: point) else { return false }

        insertionLineX = nil
        onDropTab?(from, target.index)
        return true
    }

    override func concludeDragOperation(_ sender: NSDraggingInfo?) {
        insertionLineX = nil
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let insertionLineX else { return }

        let rect = NSRect(x: insertionLineX - 2.5, y: 4, width: 5, height: max(0, bounds.height - 8))
        let path = NSBezierPath(roundedRect: rect, xRadius: 2.5, yRadius: 2.5)
        NSColor.controlAccentColor.setFill()
        path.fill()
    }

    private func updateInsertionLine(_ sender: NSDraggingInfo) {
        let point = convert(sender.draggingLocation, from: nil)
        insertionLineX = insertionTarget(at: point)?.lineX
    }

    private func insertionTarget(at point: NSPoint) -> (index: Int, lineX: CGFloat)? {
        let buttons = subviews.compactMap { $0 as? FolderTabButton }.sorted { $0.frame.minX < $1.frame.minX }
        guard !buttons.isEmpty else { return nil }

        for (index, button) in buttons.enumerated() {
            if point.x < button.frame.midX {
                return (index, button.frame.minX - 3)
            }
        }

        if let last = buttons.last {
            return (buttons.count, last.frame.maxX + 3)
        }
        return nil
    }
}

import AppKit

final class NonMovingClipView: NSClipView {
    override var mouseDownCanMoveWindow: Bool { false }
}

final class HorizontalTabScrollView: NSScrollView {
    override var mouseDownCanMoveWindow: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        contentView = NonMovingClipView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        contentView = NonMovingClipView()
    }

    override func scrollWheel(with event: NSEvent) {
        guard let contentView = documentView else {
            super.scrollWheel(with: event)
            return
        }

        let current = documentVisibleRect.origin
        let maxX = max(0, contentView.frame.width - documentVisibleRect.width)
        let delta = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) ? event.scrollingDeltaX : event.scrollingDeltaY
        let nextX = min(max(0, current.x + delta), maxX)
        contentView.scroll(NSPoint(x: nextX, y: current.y))
        reflectScrolledClipView(self.contentView)
    }
}

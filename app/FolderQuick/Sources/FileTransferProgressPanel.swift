import AppKit

final class FileTransferProgressPanel: NSPanel {
    private let titleLabel = NSTextField(labelWithString: "正在复制")
    private let detailLabel = NSTextField(labelWithString: "准备中...")
    private let progressIndicator = NSProgressIndicator()

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 128),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        title = "文件传输"
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isReleasedWhenClosed = false
        backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.96)

        let root = NSVisualEffectView()
        root.material = .hudWindow
        root.blendingMode = .behindWindow
        root.state = .active
        root.translatesAutoresizingMaskIntoConstraints = false
        contentView = root

        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textColor = .labelColor

        detailLabel.font = .systemFont(ofSize: 12, weight: .regular)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.lineBreakMode = .byTruncatingMiddle

        progressIndicator.isIndeterminate = true
        progressIndicator.style = .bar
        progressIndicator.minValue = 0
        progressIndicator.maxValue = 1
        progressIndicator.doubleValue = 0

        let stack = NSStackView(views: [titleLabel, detailLabel, progressIndicator])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 22, left: 22, bottom: 18, right: 22)
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            stack.topAnchor.constraint(equalTo: root.topAnchor),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            progressIndicator.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -44)
        ])
    }

    func show(on screen: NSScreen?, title: String, detail: String) {
        titleLabel.stringValue = title
        detailLabel.stringValue = detail
        progressIndicator.isIndeterminate = true
        progressIndicator.startAnimation(nil)

        if let screen {
            setFrameOrigin(NSPoint(
                x: screen.visibleFrame.midX - frame.width / 2,
                y: screen.visibleFrame.midY - frame.height / 2
            ))
        } else {
            center()
        }
        makeKeyAndOrderFront(nil)
    }

    func update(title: String, detail: String, completed: UInt64, total: UInt64) {
        titleLabel.stringValue = title
        detailLabel.stringValue = detail

        guard total > 0 else {
            progressIndicator.isIndeterminate = true
            progressIndicator.startAnimation(nil)
            return
        }

        if progressIndicator.isIndeterminate {
            progressIndicator.stopAnimation(nil)
            progressIndicator.isIndeterminate = false
        }
        progressIndicator.doubleValue = min(1, Double(completed) / Double(total))
    }

    func finish(title: String, detail: String) {
        progressIndicator.stopAnimation(nil)
        progressIndicator.isIndeterminate = false
        progressIndicator.doubleValue = 1
        titleLabel.stringValue = title
        detailLabel.stringValue = detail

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.orderOut(nil)
        }
    }
}

import AppKit

final class SettingsPanel: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 240),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        title = "FolderQuick 设置"
        isReleasedWhenClosed = false
        center()

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: 22, left: 24, bottom: 22, right: 24)

        let title = NSTextField(labelWithString: "第一版设置")
        title.font = .systemFont(ofSize: 18, weight: .semibold)

        let tips = [
            "菜单栏文件夹图标：显示或隐藏窗口",
            "添加文件夹：把常用目录放进顶部菜单",
            "搜索和筛选：快速缩小文件范围",
            "双击：打开文件或进入文件夹",
            "拖拽：把文件拖到其他软件"
        ]

        stack.addArrangedSubview(title)
        tips.forEach { text in
            let label = NSTextField(labelWithString: "• \(text)")
            label.font = .systemFont(ofSize: 13)
            label.textColor = .secondaryLabelColor
            stack.addArrangedSubview(label)
        }

        let wrapper = NSView()
        wrapper.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor),
            stack.topAnchor.constraint(equalTo: wrapper.topAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: wrapper.bottomAnchor)
        ])
        contentView = wrapper
    }
}

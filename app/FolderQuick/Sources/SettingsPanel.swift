import AppKit

final class SettingsPanel: NSPanel {
    var onSettingsChanged: ((AppSettings) -> Void)?

    private var settings: AppSettings
    private let positionControl = NSSegmentedControl(labels: SidebarPosition.allCases.map(\.rawValue), trackingMode: .selectOne, target: nil, action: nil)
    private let opacitySlider = NSSlider(value: 0.96, minValue: 0.55, maxValue: 1.0, target: nil, action: nil)
    private let iconSizeSlider = NSSlider(value: 132, minValue: 108, maxValue: 168, target: nil, action: nil)
    private let autoHideSlider = NSSlider(value: 0.35, minValue: 0.1, maxValue: 1.2, target: nil, action: nil)
    private let edgeDebugButton = NSButton(checkboxWithTitle: "显示边缘触发条", target: nil, action: nil)
    private let opacityValue = NSTextField(labelWithString: "")
    private let iconSizeValue = NSTextField(labelWithString: "")
    private let autoHideValue = NSTextField(labelWithString: "")

    init(settings: AppSettings) {
        self.settings = settings
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 360),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        title = "FolderQuick 设置"
        isReleasedWhenClosed = false
        center()
        buildInterface()
        applySettingsToControls()
    }

    func update(settings: AppSettings) {
        self.settings = settings
        applySettingsToControls()
    }

    private func buildInterface() {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        stack.edgeInsets = NSEdgeInsets(top: 22, left: 24, bottom: 22, right: 24)

        let title = NSTextField(labelWithString: "常用设置")
        title.font = .systemFont(ofSize: 18, weight: .semibold)
        stack.addArrangedSubview(title)

        positionControl.target = self
        positionControl.action = #selector(controlChanged)
        stack.addArrangedSubview(row(label: "窗口位置", control: positionControl, valueLabel: nil))

        opacitySlider.target = self
        opacitySlider.action = #selector(controlChanged)
        stack.addArrangedSubview(row(label: "窗口透明度", control: opacitySlider, valueLabel: opacityValue))

        iconSizeSlider.target = self
        iconSizeSlider.action = #selector(controlChanged)
        stack.addArrangedSubview(row(label: "图标大小", control: iconSizeSlider, valueLabel: iconSizeValue))

        autoHideSlider.target = self
        autoHideSlider.action = #selector(controlChanged)
        stack.addArrangedSubview(row(label: "自动隐藏延迟", control: autoHideSlider, valueLabel: autoHideValue))

        edgeDebugButton.target = self
        edgeDebugButton.action = #selector(controlChanged)
        stack.addArrangedSubview(edgeDebugButton)

        let hint = NSTextField(labelWithString: "快捷键暂时固定为 ⌥⌘F。后续版本再支持自定义。")
        hint.font = .systemFont(ofSize: 12)
        hint.textColor = .secondaryLabelColor
        stack.addArrangedSubview(hint)

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

    private func row(label: String, control: NSView, valueLabel: NSTextField?) -> NSView {
        let title = NSTextField(labelWithString: label)
        title.font = .systemFont(ofSize: 13, weight: .medium)
        title.widthAnchor.constraint(equalToConstant: 88).isActive = true

        control.translatesAutoresizingMaskIntoConstraints = false
        control.widthAnchor.constraint(equalToConstant: 190).isActive = true

        let views = valueLabel.map { [title, control, $0] } ?? [title, control]
        if let valueLabel {
            valueLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
            valueLabel.textColor = .secondaryLabelColor
            valueLabel.widthAnchor.constraint(equalToConstant: 62).isActive = true
        }

        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 12
        return stack
    }

    private func applySettingsToControls() {
        positionControl.selectedSegment = SidebarPosition.allCases.firstIndex(of: settings.sidebarPosition) ?? 0
        opacitySlider.doubleValue = settings.opacity
        iconSizeSlider.doubleValue = settings.iconSize
        autoHideSlider.doubleValue = settings.autoHideDelay
        edgeDebugButton.state = settings.showEdgeTrigger ? .on : .off
        refreshValueLabels()
    }

    private func refreshValueLabels() {
        opacityValue.stringValue = "\(Int(settings.opacity * 100))%"
        iconSizeValue.stringValue = "\(Int(settings.iconSize))"
        autoHideValue.stringValue = String(format: "%.1fs", settings.autoHideDelay)
    }

    @objc private func controlChanged() {
        let selectedIndex = max(0, positionControl.selectedSegment)
        settings.sidebarPosition = SidebarPosition.allCases[selectedIndex]
        settings.opacity = opacitySlider.doubleValue
        settings.iconSize = iconSizeSlider.doubleValue
        settings.autoHideDelay = autoHideSlider.doubleValue
        settings.showEdgeTrigger = edgeDebugButton.state == .on
        refreshValueLabels()
        onSettingsChanged?(settings)
    }
}

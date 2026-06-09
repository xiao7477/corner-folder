import AppKit

final class SettingsPanel: NSPanel {
    var onSettingsChanged: ((AppSettings) -> Void)?

    private var settings: AppSettings
    private var hasPendingChanges = false
    private var isApplyingSavedSettings = false
    private let positionButton = NSPopUpButton()
    private var triggerButtons: [NSButton] = []
    private let opacitySlider = NSSlider(value: 0.96, minValue: 0.55, maxValue: 1.0, target: nil, action: nil)
    private let iconSizeSlider = NSSlider(value: 96, minValue: 56, maxValue: 168, target: nil, action: nil)
    private let iconSpacingSlider = NSSlider(value: 12, minValue: 4, maxValue: 36, target: nil, action: nil)
    private let autoHideSlider = NSSlider(value: 0.35, minValue: 0.1, maxValue: 1.2, target: nil, action: nil)
    private let edgeEnabledButton = NSButton(checkboxWithTitle: "启用边缘触发", target: nil, action: nil)
    private let edgeDebugButton = NSButton(checkboxWithTitle: "显示边缘触发条", target: nil, action: nil)
    private let edgeHidePinnedButton = NSButton(checkboxWithTitle: "置顶时再次碰到边缘触发条则隐藏窗口", target: nil, action: nil)
    private let bottomPathButton = NSButton(checkboxWithTitle: "底部显示当前目录路径", target: nil, action: nil)
    private let sidebarButton = NSButton(checkboxWithTitle: "显示左侧文件夹侧栏", target: nil, action: nil)
    private var listInfoButtons: [NSButton] = []
    private let opacityValue = NSTextField(labelWithString: "")
    private let iconSizeValue = NSTextField(labelWithString: "")
    private let iconSpacingValue = NSTextField(labelWithString: "")
    private let autoHideValue = NSTextField(labelWithString: "")

    init(settings: AppSettings) {
        self.settings = settings
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 680),
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
        hasPendingChanges = false
        applySettingsToControls()
    }

    override func close() {
        if hasPendingChanges && !isApplyingSavedSettings {
            AppLogger.info("SettingsPanel close discarded pending changes")
        }
        hasPendingChanges = false
        isApplyingSavedSettings = false
        super.close()
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

        positionButton.addItems(withTitles: WindowAnchor.allCases.map(\.rawValue))
        positionButton.target = self
        positionButton.action = #selector(controlChanged)
        stack.addArrangedSubview(row(label: "点击图标弹出位置", control: positionButton, valueLabel: nil))

        stack.addArrangedSubview(triggerSelector())

        opacitySlider.target = self
        opacitySlider.action = #selector(controlChanged)
        stack.addArrangedSubview(row(label: "窗口透明度", control: opacitySlider, valueLabel: opacityValue))

        iconSizeSlider.target = self
        iconSizeSlider.action = #selector(controlChanged)
        stack.addArrangedSubview(row(label: "图标大小", control: iconSizeSlider, valueLabel: iconSizeValue))

        iconSpacingSlider.target = self
        iconSpacingSlider.action = #selector(controlChanged)
        stack.addArrangedSubview(row(label: "图标间距", control: iconSpacingSlider, valueLabel: iconSpacingValue))

        autoHideSlider.target = self
        autoHideSlider.action = #selector(controlChanged)
        stack.addArrangedSubview(row(label: "自动隐藏延迟", control: autoHideSlider, valueLabel: autoHideValue))

        edgeEnabledButton.target = self
        edgeEnabledButton.action = #selector(controlChanged)
        stack.addArrangedSubview(edgeEnabledButton)

        edgeDebugButton.target = self
        edgeDebugButton.action = #selector(controlChanged)
        stack.addArrangedSubview(edgeDebugButton)

        edgeHidePinnedButton.target = self
        edgeHidePinnedButton.action = #selector(controlChanged)
        stack.addArrangedSubview(edgeHidePinnedButton)

        bottomPathButton.target = self
        bottomPathButton.action = #selector(controlChanged)
        stack.addArrangedSubview(bottomPathButton)

        sidebarButton.target = self
        sidebarButton.action = #selector(controlChanged)
        stack.addArrangedSubview(sidebarButton)

        stack.addArrangedSubview(listInfoSelector())

        let hint = NSTextField(labelWithString: "快捷键暂时固定为 ⌥⌘F。后续版本再支持自定义。")
        hint.font = .systemFont(ofSize: 12)
        hint.textColor = .secondaryLabelColor
        stack.addArrangedSubview(hint)
        stack.addArrangedSubview(actionButtons())

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

    private func actionButtons() -> NSView {
        let cancel = NSButton(title: "取消", target: self, action: #selector(cancelSettings))
        let save = NSButton(title: "保存设置", target: self, action: #selector(saveSettings))
        save.keyEquivalent = "\r"
        save.bezelStyle = .rounded
        cancel.bezelStyle = .rounded

        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        let stack = NSStackView(views: [spacer, cancel, save])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.widthAnchor.constraint(equalToConstant: 512).isActive = true
        spacer.widthAnchor.constraint(greaterThanOrEqualToConstant: 1).isActive = true
        return stack
    }

    private func triggerSelector() -> NSView {
        let title = NSTextField(labelWithString: "边缘触发条")
        title.font = .systemFont(ofSize: 13, weight: .medium)
        title.widthAnchor.constraint(equalToConstant: 118).isActive = true

        let grid = NSGridView()
        grid.rowSpacing = 8
        grid.columnSpacing = 10

        triggerButtons = WindowAnchor.allCases.map { anchor in
            let button = NSButton(checkboxWithTitle: anchor.rawValue, target: self, action: #selector(controlChanged))
            button.tag = WindowAnchor.allCases.firstIndex(of: anchor) ?? 0
            return button
        }

        for row in 0..<4 {
            let start = row * 2
            let views = Array(triggerButtons[start..<(start + 2)])
            grid.addRow(with: views)
        }

        let stack = NSStackView(views: [title, grid])
        stack.orientation = .horizontal
        stack.alignment = .top
        stack.spacing = 12
        return stack
    }

    private func listInfoSelector() -> NSView {
        let title = NSTextField(labelWithString: "列表显示信息")
        title.font = .systemFont(ofSize: 13, weight: .medium)
        title.widthAnchor.constraint(equalToConstant: 118).isActive = true

        let grid = NSGridView()
        grid.rowSpacing = 8
        grid.columnSpacing = 10

        listInfoButtons = ListInfoColumn.allCases.map { column in
            let button = NSButton(checkboxWithTitle: column.rawValue, target: self, action: #selector(controlChanged))
            button.tag = ListInfoColumn.allCases.firstIndex(of: column) ?? 0
            return button
        }

        for row in 0..<2 {
            let start = row * 2
            let views = Array(listInfoButtons[start..<(start + 2)])
            grid.addRow(with: views)
        }

        let stack = NSStackView(views: [title, grid])
        stack.orientation = .horizontal
        stack.alignment = .top
        stack.spacing = 12
        return stack
    }

    private func applySettingsToControls() {
        positionButton.selectItem(at: WindowAnchor.allCases.firstIndex(of: settings.sidebarPosition) ?? 0)
        for button in triggerButtons {
            let anchor = WindowAnchor.allCases[button.tag]
            button.state = settings.triggerPositions.contains(anchor) ? .on : .off
        }
        opacitySlider.doubleValue = settings.opacity
        iconSizeSlider.doubleValue = settings.iconSize
        iconSpacingSlider.doubleValue = settings.iconSpacing
        autoHideSlider.doubleValue = settings.autoHideDelay
        edgeEnabledButton.state = settings.edgeTriggerEnabled ? .on : .off
        edgeDebugButton.state = settings.showEdgeTrigger ? .on : .off
        edgeHidePinnedButton.state = settings.hidePinnedWindowOnEdgeTrigger == true ? .on : .off
        bottomPathButton.state = settings.showBottomPath ? .on : .off
        sidebarButton.state = settings.showSidebar ? .on : .off
        for button in listInfoButtons {
            let column = ListInfoColumn.allCases[button.tag]
            button.state = settings.listInfoColumns.contains(column) ? .on : .off
        }
        refreshValueLabels()
    }

    private func refreshValueLabels() {
        opacityValue.stringValue = "\(Int(settings.opacity * 100))%"
        iconSizeValue.stringValue = "\(Int(settings.iconSize))"
        iconSpacingValue.stringValue = "\(Int(settings.iconSpacing))"
        autoHideValue.stringValue = String(format: "%.1fs", settings.autoHideDelay)
    }

    @objc private func controlChanged() {
        settings.sidebarPosition = WindowAnchor.allCases[max(0, positionButton.indexOfSelectedItem)]
        let selectedTriggers = triggerButtons.compactMap { button -> WindowAnchor? in
            button.state == .on ? WindowAnchor.allCases[button.tag] : nil
        }
        settings.triggerPositions = selectedTriggers.isEmpty ? [.right] : selectedTriggers
        settings.opacity = opacitySlider.doubleValue
        settings.iconSize = iconSizeSlider.doubleValue
        settings.iconSpacing = iconSpacingSlider.doubleValue
        settings.autoHideDelay = autoHideSlider.doubleValue
        settings.edgeTriggerEnabled = edgeEnabledButton.state == .on
        settings.showEdgeTrigger = edgeDebugButton.state == .on
        settings.hidePinnedWindowOnEdgeTrigger = edgeHidePinnedButton.state == .on
        settings.showBottomPath = bottomPathButton.state == .on
        settings.showSidebar = sidebarButton.state == .on
        let columns = listInfoButtons.compactMap { button -> ListInfoColumn? in
            button.state == .on ? ListInfoColumn.allCases[button.tag] : nil
        }
        settings.listInfoColumns = columns.isEmpty ? [.kind] : columns
        refreshValueLabels()
        hasPendingChanges = true
        AppLogger.info("SettingsPanel changed pending settings")
    }

    @objc private func saveSettings() {
        AppLogger.info("SettingsPanel save requested")
        let nextSettings = settings
        hasPendingChanges = false
        isApplyingSavedSettings = true
        onSettingsChanged?(nextSettings)
        close()
    }

    @objc private func cancelSettings() {
        AppLogger.info("SettingsPanel cancel requested")
        close()
    }
}

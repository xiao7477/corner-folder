import AppKit

final class FileListRowView: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("FileListRowView")

    private let iconView = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")
    var isDropHovered: Bool = false {
        didSet { updateHoverState() }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        build()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        build()
    }

    private func build() {
        wantsLayer = true
        layer?.cornerRadius = 6

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.imageScaling = .scaleProportionallyUpOrDown

        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.lineBreakMode = .byTruncatingMiddle
        nameLabel.font = .systemFont(ofSize: 13, weight: .medium)

        detailLabel.translatesAutoresizingMaskIntoConstraints = false
        detailLabel.lineBreakMode = .byTruncatingMiddle
        detailLabel.alignment = .right
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.font = .systemFont(ofSize: 12)

        addSubview(iconView)
        addSubview(nameLabel)
        addSubview(detailLabel)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 22),
            iconView.heightAnchor.constraint(equalToConstant: 22),

            nameLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
            nameLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: detailLabel.leadingAnchor, constant: -10),

            detailLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            detailLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            detailLabel.widthAnchor.constraint(equalToConstant: 92)
        ])
    }

    func configure(entry: FileEntry, depth: Int) {
        isDropHovered = false
        let icon = NSWorkspace.shared.icon(forFile: entry.url.path)
        icon.size = NSSize(width: 22, height: 22)
        iconView.image = icon
        nameLabel.stringValue = entry.name
        detailLabel.stringValue = entry.isDirectory ? "文件夹" : entry.kind.rawValue
    }

    private func updateHoverState() {
        layer?.backgroundColor = isDropHovered ? NSColor.controlAccentColor.withAlphaComponent(0.24).cgColor : NSColor.clear.cgColor
        nameLabel.textColor = isDropHovered ? .controlAccentColor : .labelColor
        detailLabel.textColor = isDropHovered ? .controlAccentColor : .secondaryLabelColor
    }
}

final class FileNode: NSObject {
    let entry: FileEntry
    weak var parent: FileNode?
    var children: [FileNode]?

    init(entry: FileEntry, parent: FileNode? = nil) {
        self.entry = entry
        self.parent = parent
    }
}

import AppKit
import QuickLookThumbnailing

final class FileItemRootView: NSView {
    weak var renameField: NSTextField?

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard bounds.contains(point) else { return nil }
        if let renameField,
           !renameField.isHidden,
           renameField.frame.contains(convert(point, to: renameField.superview)) {
            return renameField.hitTest(convert(point, to: renameField))
        }
        return nil
    }
}

final class FileItemView: NSCollectionViewItem, NSTextFieldDelegate {
    static let identifier = NSUserInterfaceItemIdentifier("FileItemView")

    private let thumbnailView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let selectionView = NSView()
    private let renameField = NSTextField()
    private var thumbnailWidthConstraint: NSLayoutConstraint?
    private var thumbnailHeightConstraint: NSLayoutConstraint?
    private var selectionWidthConstraint: NSLayoutConstraint?
    private var representedURL: URL?
    private var originalName = ""
    private var isRenaming = false
    var onRenameCommit: ((URL, String) -> Void)?
    var isDropHovered: Bool = false {
        didSet { updateBackground() }
    }

    override func loadView() {
        let rootView = FileItemRootView(frame: NSRect(x: 0, y: 0, width: 132, height: 138))
        view = rootView
        view.wantsLayer = true

        selectionView.translatesAutoresizingMaskIntoConstraints = false
        selectionView.wantsLayer = true
        selectionView.layer?.cornerRadius = 8
        selectionView.layer?.backgroundColor = NSColor.clear.cgColor
        rootView.renameField = renameField

        thumbnailView.translatesAutoresizingMaskIntoConstraints = false
        thumbnailView.imageScaling = .scaleProportionallyUpOrDown
        thumbnailView.wantsLayer = true
        thumbnailView.layer?.cornerRadius = 6

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.alignment = .center
        titleLabel.maximumNumberOfLines = 2
        titleLabel.lineBreakMode = .byTruncatingMiddle
        titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        titleLabel.textColor = .labelColor

        renameField.translatesAutoresizingMaskIntoConstraints = false
        renameField.isHidden = true
        renameField.alignment = .center
        renameField.lineBreakMode = .byTruncatingMiddle
        renameField.bezelStyle = .roundedBezel
        renameField.font = titleLabel.font
        renameField.target = self
        renameField.action = #selector(commitRename)
        renameField.delegate = self

        view.addSubview(selectionView)
        selectionView.addSubview(thumbnailView)
        selectionView.addSubview(titleLabel)
        selectionView.addSubview(renameField)

        thumbnailWidthConstraint = thumbnailView.widthAnchor.constraint(equalToConstant: 80)
        thumbnailHeightConstraint = thumbnailView.heightAnchor.constraint(equalToConstant: 70)
        selectionWidthConstraint = selectionView.widthAnchor.constraint(equalToConstant: 112)

        NSLayoutConstraint.activate([
            selectionView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            selectionView.topAnchor.constraint(equalTo: view.topAnchor),
            selectionWidthConstraint!,
            selectionView.bottomAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 5),

            thumbnailView.topAnchor.constraint(equalTo: selectionView.topAnchor, constant: 4),
            thumbnailView.centerXAnchor.constraint(equalTo: selectionView.centerXAnchor),
            thumbnailWidthConstraint!,
            thumbnailHeightConstraint!,
            titleLabel.topAnchor.constraint(equalTo: thumbnailView.bottomAnchor, constant: 8),
            titleLabel.leadingAnchor.constraint(equalTo: selectionView.leadingAnchor, constant: 3),
            titleLabel.trailingAnchor.constraint(equalTo: selectionView.trailingAnchor, constant: -3),

            renameField.topAnchor.constraint(equalTo: titleLabel.topAnchor, constant: -2),
            renameField.leadingAnchor.constraint(equalTo: selectionView.leadingAnchor, constant: 0),
            renameField.trailingAnchor.constraint(equalTo: selectionView.trailingAnchor, constant: 0)
        ])
    }

    override var isSelected: Bool {
        didSet {
            updateBackground()
        }
    }

    func configure(with entry: FileEntry, iconSize: Double) {
        representedURL = entry.url
        originalName = entry.name
        isDropHovered = false
        titleLabel.isHidden = false
        renameField.isHidden = true
        titleLabel.stringValue = entry.name
        let thumbnailSize = max(34, min(iconSize * 0.78, iconSize - 12))
        thumbnailWidthConstraint?.constant = thumbnailSize
        thumbnailHeightConstraint?.constant = thumbnailSize * 0.9
        selectionWidthConstraint?.constant = min(iconSize + 12, max(thumbnailSize + 14, 88))
        titleLabel.font = .systemFont(ofSize: iconSize < 76 ? 11 : (iconSize >= 150 ? 14 : 13), weight: .medium)
        renameField.font = titleLabel.font
        thumbnailView.image = fallbackIcon(for: entry)
        loadThumbnail(for: entry)
    }

    func beginRenaming() {
        guard let window = view.window else { return }
        isRenaming = true
        renameField.stringValue = originalName
        titleLabel.isHidden = true
        renameField.isHidden = false
        window.makeFirstResponder(renameField)
        renameField.currentEditor()?.selectAll(nil)
    }

    @objc private func commitRename() {
        finishRenaming(shouldCommit: true)
    }

    private func finishRenaming(shouldCommit: Bool) {
        guard isRenaming else { return }
        isRenaming = false
        renameField.isHidden = true
        titleLabel.isHidden = false
        guard shouldCommit,
              let representedURL,
              !renameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        onRenameCommit?(representedURL, renameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    override func cancelOperation(_ sender: Any?) {
        finishRenaming(shouldCommit: false)
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        finishRenaming(shouldCommit: true)
    }

    private func updateBackground() {
        if isDropHovered {
            selectionView.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.38).cgColor
            titleLabel.textColor = .controlAccentColor
        } else {
            selectionView.layer?.backgroundColor = isSelected ? NSColor.controlAccentColor.withAlphaComponent(0.24).cgColor : NSColor.clear.cgColor
            titleLabel.textColor = .labelColor
        }
    }

    private func fallbackIcon(for entry: FileEntry) -> NSImage {
        let icon = NSWorkspace.shared.icon(forFile: entry.url.path)
        icon.size = NSSize(width: 80, height: 70)
        return icon
    }

    private func loadThumbnail(for entry: FileEntry) {
        let request = QLThumbnailGenerator.Request(
            fileAt: entry.url,
            size: CGSize(width: 512, height: 460),
            scale: NSScreen.main?.backingScaleFactor ?? 2,
            representationTypes: .all
        )

        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { [weak self] thumbnail, _ in
            guard let self, self.representedURL == entry.url, let thumbnail else { return }
            DispatchQueue.main.async {
                guard self.representedURL == entry.url else { return }
                self.thumbnailView.image = thumbnail.nsImage
            }
        }
    }
}

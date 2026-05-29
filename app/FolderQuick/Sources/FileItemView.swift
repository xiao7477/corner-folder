import AppKit
import QuickLookThumbnailing

final class FileItemView: NSCollectionViewItem {
    static let identifier = NSUserInterfaceItemIdentifier("FileItemView")

    private let thumbnailView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let selectionView = NSView()
    private var thumbnailWidthConstraint: NSLayoutConstraint?
    private var thumbnailHeightConstraint: NSLayoutConstraint?
    private var representedURL: URL?
    var isDropHovered: Bool = false {
        didSet { updateBackground() }
    }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 132, height: 138))
        view.wantsLayer = true

        selectionView.translatesAutoresizingMaskIntoConstraints = false
        selectionView.wantsLayer = true
        selectionView.layer?.cornerRadius = 8
        selectionView.layer?.backgroundColor = NSColor.clear.cgColor

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

        view.addSubview(selectionView)
        selectionView.addSubview(thumbnailView)
        selectionView.addSubview(titleLabel)

        thumbnailWidthConstraint = thumbnailView.widthAnchor.constraint(equalToConstant: 80)
        thumbnailHeightConstraint = thumbnailView.heightAnchor.constraint(equalToConstant: 70)

        NSLayoutConstraint.activate([
            selectionView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            selectionView.topAnchor.constraint(equalTo: view.topAnchor, constant: 2),
            selectionView.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.86),
            selectionView.bottomAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),

            thumbnailView.topAnchor.constraint(equalTo: selectionView.topAnchor, constant: 8),
            thumbnailView.centerXAnchor.constraint(equalTo: selectionView.centerXAnchor),
            thumbnailWidthConstraint!,
            thumbnailHeightConstraint!,
            titleLabel.topAnchor.constraint(equalTo: thumbnailView.bottomAnchor, constant: 10),
            titleLabel.leadingAnchor.constraint(equalTo: selectionView.leadingAnchor, constant: 6),
            titleLabel.trailingAnchor.constraint(equalTo: selectionView.trailingAnchor, constant: -6)
        ])
    }

    override var isSelected: Bool {
        didSet {
            updateBackground()
        }
    }

    func configure(with entry: FileEntry, iconSize: Double) {
        representedURL = entry.url
        isDropHovered = false
        titleLabel.stringValue = entry.name
        let thumbnailSize = max(34, min(iconSize * 0.78, iconSize - 12))
        thumbnailWidthConstraint?.constant = thumbnailSize
        thumbnailHeightConstraint?.constant = thumbnailSize * 0.9
        titleLabel.font = .systemFont(ofSize: iconSize < 76 ? 11 : (iconSize >= 150 ? 14 : 13), weight: .medium)
        thumbnailView.image = fallbackIcon(for: entry)
        loadThumbnail(for: entry)
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

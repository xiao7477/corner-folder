import AppKit
import QuickLookThumbnailing

final class FileItemView: NSCollectionViewItem {
    static let identifier = NSUserInterfaceItemIdentifier("FileItemView")

    private let thumbnailView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private var thumbnailWidthConstraint: NSLayoutConstraint?
    private var thumbnailHeightConstraint: NSLayoutConstraint?
    private var representedURL: URL?

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 132, height: 138))
        view.wantsLayer = true
        view.layer?.cornerRadius = 8

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

        view.addSubview(thumbnailView)
        view.addSubview(titleLabel)

        thumbnailWidthConstraint = thumbnailView.widthAnchor.constraint(equalToConstant: 80)
        thumbnailHeightConstraint = thumbnailView.heightAnchor.constraint(equalToConstant: 70)

        NSLayoutConstraint.activate([
            thumbnailView.topAnchor.constraint(equalTo: view.topAnchor, constant: 10),
            thumbnailView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            thumbnailWidthConstraint!,
            thumbnailHeightConstraint!,
            titleLabel.topAnchor.constraint(equalTo: thumbnailView.bottomAnchor, constant: 10),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 6),
            titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -6)
        ])
    }

    override var isSelected: Bool {
        didSet {
            view.layer?.backgroundColor = isSelected ? NSColor.controlAccentColor.withAlphaComponent(0.22).cgColor : NSColor.clear.cgColor
        }
    }

    func configure(with entry: FileEntry, iconSize: Double) {
        representedURL = entry.url
        titleLabel.stringValue = entry.name
        let thumbnailSize = max(66, min(112, iconSize * 0.62))
        thumbnailWidthConstraint?.constant = thumbnailSize
        thumbnailHeightConstraint?.constant = thumbnailSize * 0.88
        titleLabel.font = .systemFont(ofSize: iconSize >= 150 ? 14 : 13, weight: .medium)
        thumbnailView.image = fallbackIcon(for: entry)
        loadThumbnail(for: entry)
    }

    private func fallbackIcon(for entry: FileEntry) -> NSImage {
        let icon = NSWorkspace.shared.icon(forFile: entry.url.path)
        icon.size = NSSize(width: 80, height: 70)
        return icon
    }

    private func loadThumbnail(for entry: FileEntry) {
        let request = QLThumbnailGenerator.Request(
            fileAt: entry.url,
            size: CGSize(width: 160, height: 140),
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

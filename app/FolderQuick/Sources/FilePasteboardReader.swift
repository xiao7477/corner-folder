import AppKit

enum FilePasteboardReader {
    static let supportedTypes: [NSPasteboard.PasteboardType] = [
        .fileURL,
        .URL,
        .string,
        NSPasteboard.PasteboardType("NSFilenamesPboardType")
    ]

    static func fileURLs(from pasteboard: NSPasteboard) -> [URL] {
        if let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [NSURL] {
            let fileURLs = urls.compactMap { $0 as URL }.filter(\.isFileURL)
            if !fileURLs.isEmpty { return fileURLs }
        }

        if let fileNames = pasteboard.propertyList(
            forType: NSPasteboard.PasteboardType("NSFilenamesPboardType")
        ) as? [String] {
            let urls = fileNames
                .filter { FileManager.default.fileExists(atPath: $0) }
                .map { URL(fileURLWithPath: $0) }
            if !urls.isEmpty { return urls }
        }

        for type in [NSPasteboard.PasteboardType.fileURL, .URL, .string] {
            if let urls = urlsFromString(pasteboard.string(forType: type)), !urls.isEmpty {
                return urls
            }
        }

        return pasteboard.pasteboardItems?.flatMap { item in
            item.types.compactMap { type in item.string(forType: type) }
        }
        .flatMap { urlsFromString($0) ?? [] } ?? []
    }

    private static func urlsFromString(_ value: String?) -> [URL]? {
        guard let value else { return nil }
        let urls = value
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .compactMap { text -> URL? in
                if let url = URL(string: text), url.isFileURL {
                    return url
                }
                let expanded = (text as NSString).expandingTildeInPath
                return FileManager.default.fileExists(atPath: expanded) ? URL(fileURLWithPath: expanded) : nil
            }
        return urls.isEmpty ? nil : urls
    }
}

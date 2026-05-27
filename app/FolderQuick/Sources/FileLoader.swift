import AppKit

final class FileLoader {
    func loadFiles(in folderURL: URL) -> [FileEntry] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .contentModificationDateKey, .isHiddenKey]
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: keys,
            options: [.skipsPackageDescendants]
        ) else {
            return []
        }

        return urls
            .filter { url in
                let values = try? url.resourceValues(forKeys: [.isHiddenKey])
                return values?.isHidden != true
            }
            .map(FileEntry.make)
            .sorted { left, right in
                if left.isDirectory != right.isDirectory {
                    return left.isDirectory && !right.isDirectory
                }
                return left.name.localizedStandardCompare(right.name) == .orderedAscending
            }
    }
}

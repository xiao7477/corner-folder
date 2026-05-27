import AppKit

final class FolderStore {
    static let shared = FolderStore()

    private let foldersKey = "folderquick.folders"
    private let selectedFolderKey = "folderquick.selectedFolder"
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    private init() {}

    func loadFolders() -> [FolderEntry] {
        guard let data = UserDefaults.standard.data(forKey: foldersKey),
              let folders = try? decoder.decode([FolderEntry].self, from: data) else {
            return []
        }
        return folders
    }

    func saveFolders(_ folders: [FolderEntry]) {
        guard let data = try? encoder.encode(folders) else { return }
        UserDefaults.standard.set(data, forKey: foldersKey)
    }

    func selectedFolderID() -> UUID? {
        guard let text = UserDefaults.standard.string(forKey: selectedFolderKey) else { return nil }
        return UUID(uuidString: text)
    }

    func saveSelectedFolderID(_ id: UUID?) {
        UserDefaults.standard.set(id?.uuidString, forKey: selectedFolderKey)
    }

    func bookmark(for url: URL) throws -> Data {
        try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    func resolve(_ folder: FolderEntry) -> URL? {
        var stale = false
        guard let url = try? URL(
            resolvingBookmarkData: folder.bookmarkData,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ) else {
            return nil
        }
        _ = url.startAccessingSecurityScopedResource()
        return url
    }
}

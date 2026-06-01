import AppKit

enum FileKind: String, CaseIterable {
    case all = "全部"
    case folder = "文件夹"
    case image = "图片"
    case document = "文档"
    case video = "视频"
    case audio = "音频"
    case other = "其他"
}

enum WindowAnchor: String, Codable, CaseIterable {
    case right = "右侧"
    case left = "左侧"
    case top = "上方"
    case bottom = "下方"
    case topLeft = "左上角"
    case topRight = "右上角"
    case bottomLeft = "左下角"
    case bottomRight = "右下角"
}

enum FileViewMode: String, Codable, CaseIterable {
    case grid = "图标"
    case list = "列表"
}

struct AppSettings: Codable, Equatable {
    var sidebarPosition: WindowAnchor = .right
    var triggerPositions: [WindowAnchor] = [.right]
    var windowWidth: Double = 780
    var windowHeight: Double = 720
    var opacity: Double = 0.96
    var iconSize: Double = 96
    var iconSpacing: Double = 12
    var edgeTriggerEnabled: Bool = true
    var showEdgeTrigger: Bool = false
    var hidePinnedWindowOnEdgeTrigger: Bool? = false
    var showBottomPath: Bool = true
    var autoHideDelay: Double = 0.35
    var viewMode: FileViewMode = .grid
}

struct FolderEntry: Codable, Equatable {
    let id: UUID
    var name: String
    var bookmarkData: Data
}

struct FileEntry: Hashable {
    let url: URL
    let name: String
    let isDirectory: Bool
    let modifiedAt: Date?
    let kind: FileKind
}

extension FileEntry {
    static func make(url: URL) -> FileEntry {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .contentModificationDateKey])
        let isDirectory = values?.isDirectory == true
        return FileEntry(
            url: url,
            name: url.lastPathComponent,
            isDirectory: isDirectory,
            modifiedAt: values?.contentModificationDate,
            kind: Self.kind(for: url, isDirectory: isDirectory)
        )
    }

    private static func kind(for url: URL, isDirectory: Bool) -> FileKind {
        if isDirectory { return .folder }
        let ext = url.pathExtension.lowercased()
        if ["png", "jpg", "jpeg", "gif", "heic", "webp", "tiff", "svg"].contains(ext) { return .image }
        if ["pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "txt", "md", "rtf", "csv"].contains(ext) { return .document }
        if ["mp4", "mov", "m4v", "avi", "mkv", "webm"].contains(ext) { return .video }
        if ["mp3", "m4a", "wav", "aac", "flac"].contains(ext) { return .audio }
        return .other
    }
}

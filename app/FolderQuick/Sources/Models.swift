import AppKit

enum AppLogger {
    private static let queue = DispatchQueue(label: "local.folderquick.logger")

    static var logURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("FolderQuick", isDirectory: true).appendingPathComponent("FolderQuick.log")
    }

    static func info(_ message: String) {
        write(level: "INFO", message: message)
    }

    static func error(_ message: String) {
        write(level: "ERROR", message: message)
    }

    private static func write(level: String, message: String) {
        let line = "[\(timestamp())] [\(level)] \(message)\n"
        queue.async {
            do {
                let url = logURL
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                guard let data = line.data(using: .utf8) else { return }
                if FileManager.default.fileExists(atPath: url.path) {
                    let handle = try FileHandle(forWritingTo: url)
                    defer { try? handle.close() }
                    try handle.seekToEnd()
                    try handle.write(contentsOf: data)
                } else {
                    try data.write(to: url)
                }
            } catch {
                NSLog("FolderQuick log failed: \(error.localizedDescription)")
            }
        }
    }

    private static func timestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }
}

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

enum FileSortMode: String, Codable, CaseIterable {
    case name = "名称"
    case kind = "种类"
    case dateModified = "修改日期"
    case dateCreated = "创建日期"
    case size = "大小"
}

enum ListInfoColumn: String, Codable, CaseIterable {
    case kind = "种类"
    case dateModified = "修改日期"
    case dateCreated = "创建日期"
    case size = "大小"
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
    var sortMode: FileSortMode = .name
    var sortAscending: Bool = true
    var showSidebar: Bool = false
    var listInfoColumns: [ListInfoColumn] = [.kind]
    var pinnedFilePaths: [String] = []

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sidebarPosition = try container.decodeIfPresent(WindowAnchor.self, forKey: .sidebarPosition) ?? .right
        triggerPositions = try container.decodeIfPresent([WindowAnchor].self, forKey: .triggerPositions) ?? [.right]
        windowWidth = try container.decodeIfPresent(Double.self, forKey: .windowWidth) ?? 780
        windowHeight = try container.decodeIfPresent(Double.self, forKey: .windowHeight) ?? 720
        opacity = try container.decodeIfPresent(Double.self, forKey: .opacity) ?? 0.96
        iconSize = try container.decodeIfPresent(Double.self, forKey: .iconSize) ?? 96
        iconSpacing = try container.decodeIfPresent(Double.self, forKey: .iconSpacing) ?? 12
        edgeTriggerEnabled = try container.decodeIfPresent(Bool.self, forKey: .edgeTriggerEnabled) ?? true
        showEdgeTrigger = try container.decodeIfPresent(Bool.self, forKey: .showEdgeTrigger) ?? false
        hidePinnedWindowOnEdgeTrigger = try container.decodeIfPresent(Bool.self, forKey: .hidePinnedWindowOnEdgeTrigger) ?? false
        showBottomPath = try container.decodeIfPresent(Bool.self, forKey: .showBottomPath) ?? true
        autoHideDelay = try container.decodeIfPresent(Double.self, forKey: .autoHideDelay) ?? 0.35
        viewMode = try container.decodeIfPresent(FileViewMode.self, forKey: .viewMode) ?? .grid
        sortMode = try container.decodeIfPresent(FileSortMode.self, forKey: .sortMode) ?? .name
        sortAscending = try container.decodeIfPresent(Bool.self, forKey: .sortAscending) ?? true
        showSidebar = try container.decodeIfPresent(Bool.self, forKey: .showSidebar) ?? false
        listInfoColumns = try container.decodeIfPresent([ListInfoColumn].self, forKey: .listInfoColumns) ?? [.kind]
        pinnedFilePaths = try container.decodeIfPresent([String].self, forKey: .pinnedFilePaths) ?? []
    }
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
    let createdAt: Date?
    let fileSize: Int?
    let kind: FileKind
}

extension FileEntry {
    static func make(url: URL) -> FileEntry {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .contentModificationDateKey, .creationDateKey, .fileSizeKey])
        let isDirectory = values?.isDirectory == true
        return FileEntry(
            url: url,
            name: url.lastPathComponent,
            isDirectory: isDirectory,
            modifiedAt: values?.contentModificationDate,
            createdAt: values?.creationDate,
            fileSize: values?.fileSize,
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

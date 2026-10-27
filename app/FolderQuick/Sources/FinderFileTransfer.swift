import AppKit

enum FinderFileTransfer {
    static func perform(sources: [URL], to destination: URL, operation: FileImportOperation) throws {
        guard !sources.isEmpty else { return }

        let sourceItems = sources
            .map { "POSIX file \(appleScriptString($0.path))" }
            .joined(separator: ", ")
        let destinationFolder = "POSIX file \(appleScriptString(destination.path))"
        let command = operation == .move ? "move" : "duplicate"
        let source = """
        tell application id "com.apple.finder"
            set sourceItems to {\(sourceItems)}
            set destinationFolder to \(destinationFolder)
            \(command) sourceItems to destinationFolder
        end tell
        """

        guard let script = NSAppleScript(source: source) else {
            throw transferError("无法准备 Finder 文件传输命令。")
        }

        var errorInfo: NSDictionary?
        script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            let message = errorInfo["NSAppleScriptErrorMessage"] as? String
                ?? errorInfo.description
            throw transferError(message)
        }
    }

    private static func appleScriptString(_ value: String) -> String {
        var pieces: [String] = []
        var literal = ""

        func flushLiteral() {
            guard !literal.isEmpty else { return }
            let escaped = literal
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            pieces.append("\"\(escaped)\"")
            literal = ""
        }

        for scalar in value.unicodeScalars {
            if scalar.value < 32 || (127...159).contains(scalar.value) || scalar.value == 0x2028 || scalar.value == 0x2029 {
                flushLiteral()
                pieces.append("(character id \(scalar.value))")
            } else {
                literal.unicodeScalars.append(scalar)
            }
        }
        flushLiteral()

        return pieces.isEmpty ? "\"\"" : pieces.joined(separator: " & ")
    }

    private static func transferError(_ message: String) -> NSError {
        NSError(
            domain: "FolderQuick.FinderFileTransfer",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }
}

import Foundation

public enum ProjectLabel {
    private static let workspaceRoots: Set<String> = ["projects", "Desktop", "Documents", "Downloads"]

    public static func resolve(directory: String, title: String?,
                               home: String = NSHomeDirectory(),
                               fileManager: FileManager = .default) -> String {
        let dirURL = URL(fileURLWithPath: directory).standardizedFileURL
        if let root = gitRoot(from: dirURL, fileManager: fileManager) {
            return root.lastPathComponent
        }

        let base = dirURL.lastPathComponent
        let homeURL = URL(fileURLWithPath: home).standardizedFileURL
        if dirURL.path == homeURL.path || workspaceRoots.contains(base) {
            if let title = normalizedTitle(title) { return title }
        }
        return base
    }

    private static func normalizedTitle(_ title: String?) -> String? {
        guard let title else { return nil }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(28))
    }

    private static func gitRoot(from start: URL, fileManager: FileManager) -> URL? {
        var current = start
        while true {
            if fileManager.fileExists(atPath: current.appendingPathComponent(".git").path) {
                return current
            }
            let parent = current.deletingLastPathComponent()
            if parent.path == current.path { return nil }
            current = parent
        }
    }
}

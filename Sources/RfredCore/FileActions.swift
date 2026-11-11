import Foundation

public enum FileActionID: String, CaseIterable, Sendable, Equatable {
    case recentDocuments
    case showPackageContents
    case open
    case openWith
    case reveal
    case getInfo
    case copyTo
    case moveTo
    case delete
    case copyReplacing
    case moveReplacing
    case browseFolder
    case openTerminal
    case copyPath
    case copyFile
}

public struct FileActionItem: Equatable, Sendable, Identifiable {
    public var id: FileActionID
    public var title: String
    public var subtitle: String

    public init(id: FileActionID, title: String, subtitle: String) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
    }
}

public enum FileActions {
    /// Right-click and action-panel commands for an application result.
    /// The order matches the application file-action list: recent documents
    /// first, then package, open, Finder, copy and move, then terminal and clipboard.
    public static func items(kind: String, path: String) -> [FileActionItem] {
        guard kind == "app", path.hasPrefix("/") else { return [] }
        return [
            FileActionItem(id: .recentDocuments, title: "Recent Documents...", subtitle: "Show recent documents for application"),
            FileActionItem(id: .showPackageContents, title: "Show Package Contents", subtitle: "Open the package contents in Finder"),
            FileActionItem(id: .open, title: "Open", subtitle: "Open the application"),
            FileActionItem(id: .openWith, title: "Open with...", subtitle: "Choose an application"),
            FileActionItem(id: .reveal, title: "Reveal in Finder", subtitle: "Reveal the application in Finder"),
            FileActionItem(id: .getInfo, title: "Get Info", subtitle: "Show the Finder Info window"),
            FileActionItem(id: .copyTo, title: "Copy to...", subtitle: "Copy into a folder"),
            FileActionItem(id: .moveTo, title: "Move to...", subtitle: "Move into a folder"),
            FileActionItem(id: .delete, title: "Delete", subtitle: "Move to the Trash"),
            FileActionItem(id: .copyReplacing, title: "Copy [with Replace] to...", subtitle: "Copy and replace an existing item"),
            FileActionItem(id: .moveReplacing, title: "Move [with Replace] to...", subtitle: "Move and replace an existing item"),
            FileActionItem(id: .browseFolder, title: "Browse Folder in Rfred", subtitle: "Open the enclosing folder"),
            FileActionItem(id: .openTerminal, title: "Open Terminal Here", subtitle: "Open a terminal in the enclosing folder"),
            FileActionItem(id: .copyPath, title: "Copy Path to Clipboard", subtitle: "Copy the path"),
            FileActionItem(id: .copyFile, title: "Copy File to Clipboard", subtitle: "Copy the file for pasting in Finder"),
        ]
    }
}

public enum RecentDocuments {
    public struct Item: Equatable, Sendable, Identifiable {
        public var name: String
        public var path: String
        public var id: String { path }

        public init(name: String, path: String) {
            self.name = name
            self.path = path
        }
    }

    /// Bookmark blobs stored in a shared-file-list property list. Launch Services
    /// writes each recent document as bookmark data whose bytes start with "book".
    public static func bookmarkBlobs(in plist: Data) -> [Data] {
        guard let root = try? PropertyListSerialization.propertyList(from: plist, options: [], format: nil) as? [String: Any],
              let objects = root["$objects"] as? [Any] else { return [] }
        return objects.compactMap { object in
            guard let data = object as? Data, data.count >= 8 else { return nil }
            guard data.starts(with: Data("book".utf8)) else { return nil }
            return data
        }
    }

    public static func urls(forAppAt path: String, limit: Int = 20) -> [Item] {
        guard limit > 0, let bundleID = Bundle(url: URL(fileURLWithPath: path))?.bundleIdentifier else { return [] }
        guard let file = listFile(bundleID: bundleID), let data = try? Data(contentsOf: file) else { return [] }
        var items: [Item] = []
        for blob in bookmarkBlobs(in: data) {
            var stale = false
            guard let url = try? URL(
                resolvingBookmarkData: blob,
                options: [.withoutUI, .withoutMounting],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            ) else { continue }
            let resolved = url.path
            guard resolved.hasPrefix("/"), FileManager.default.fileExists(atPath: resolved) else { continue }
            if items.contains(where: { $0.path == resolved }) { continue }
            items.append(Item(name: url.lastPathComponent, path: resolved))
            if items.count >= limit { break }
        }
        return items
    }

    private static func listFile(bundleID: String) -> URL? {
        let folder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
            "Library/Application Support/com.apple.sharedfilelist/com.apple.LSSharedFileList.ApplicationRecentDocuments",
            isDirectory: true
        )
        let wanted = bundleID.lowercased()
        for ext in ["sfl4", "sfl3", "sfl2"] {
            let exact = folder.appendingPathComponent("\(wanted).\(ext)")
            if FileManager.default.fileExists(atPath: exact.path) { return exact }
        }
        guard let names = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else { return nil }
        return names.first { url in
            let ext = url.pathExtension.lowercased()
            guard ext == "sfl4" || ext == "sfl3" || ext == "sfl2" else { return false }
            return url.deletingPathExtension().lastPathComponent.lowercased() == wanted
        }
    }
}

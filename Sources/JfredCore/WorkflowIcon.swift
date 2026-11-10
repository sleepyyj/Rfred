import Foundation

/// How a script-filter or workflow result icon should be shown in the launcher.
public enum WorkflowIconRef: Equatable, Sendable {
    /// Load the image contents at this path (`.icns`, `.png`, and other image files).
    case image(String)
    /// Use the Finder / workspace icon for this file or application.
    case fileIcon(String)
    /// Use the system icon for a UTI or filename extension.
    case fileType(String)
    /// SF Symbol name.
    case symbol(String)

    /// Resource string consumed by the launcher (`image:`, `file:`, `filetype:`, `symbol:`).
    public var resource: String {
        switch self {
        case .image(let path): return "image:\(path)"
        case .fileIcon(let path): return "file:\(path)"
        case .fileType(let type): return "filetype:\(type)"
        case .symbol(let name): return "symbol:\(name)"
        }
    }
}

/// Resolves the many icon forms imported workflows emit into a single ref.
public enum WorkflowIcon {
    public static let imageExtensions: Set<String> = [
        "icns", "png", "jpg", "jpeg", "gif", "tif", "tiff", "webp", "bmp", "heic", "heif", "pdf", "svg"
    ]

    public static func isImagePath(_ path: String) -> Bool {
        imageExtensions.contains((path as NSString).pathExtension.lowercased())
    }

    public static func resolve(
        path: String,
        type: String = "",
        workflowRoot: String? = nil,
        workflowSymbol: String = "puzzlepiece.extension",
        objectUID: String? = nil
    ) -> WorkflowIconRef {
        let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedType = type.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let symbol = workflowSymbol.isEmpty ? "puzzlepiece.extension" : workflowSymbol

        if trimmedPath.hasPrefix("http://") || trimmedPath.hasPrefix("https://") {
            return .symbol("globe")
        }

        if trimmedType == "filetype" {
            if !trimmedPath.isEmpty { return .fileType(trimmedPath) }
            return fallback(root: workflowRoot, objectUID: objectUID, symbol: symbol)
        }

        if trimmedType == "fileicon" {
            let resolved = resolvePath(trimmedPath, workflowRoot: workflowRoot)
            if !resolved.isEmpty, FileManager.default.fileExists(atPath: resolved) {
                return .fileIcon(resolved)
            }
            return fallback(root: workflowRoot, objectUID: objectUID, symbol: symbol)
        }

        if !trimmedPath.isEmpty {
            let resolved = resolvePath(trimmedPath, workflowRoot: workflowRoot)
            if FileManager.default.fileExists(atPath: resolved) {
                return isImagePath(resolved) ? .image(resolved) : .fileIcon(resolved)
            }
        }

        return fallback(root: workflowRoot, objectUID: objectUID, symbol: symbol)
    }

    public static func resolvePath(_ path: String, workflowRoot: String?) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if trimmed.hasPrefix("~") { return (trimmed as NSString).expandingTildeInPath }
        if (trimmed as NSString).isAbsolutePath { return trimmed }
        guard let root = workflowRoot, !root.isEmpty else { return trimmed }
        return URL(fileURLWithPath: root, isDirectory: true).appendingPathComponent(trimmed).path
    }

    private static func fallback(root: String?, objectUID: String?, symbol: String) -> WorkflowIconRef {
        if let root, !root.isEmpty {
            if let objectUID, !objectUID.isEmpty {
                for ext in ["png", "icns", "jpg", "jpeg"] {
                    let candidate = URL(fileURLWithPath: root, isDirectory: true)
                        .appendingPathComponent("\(objectUID).\(ext)").path
                    if FileManager.default.fileExists(atPath: candidate) { return .image(candidate) }
                }
            }
            for name in ["icon.png", "icon.icns", "icon.jpg", "icon.jpeg", "icon.pdf", "icon.svg"] {
                let candidate = URL(fileURLWithPath: root, isDirectory: true)
                    .appendingPathComponent(name).path
                if FileManager.default.fileExists(atPath: candidate) { return .image(candidate) }
            }
        }
        return .symbol(symbol)
    }
}


extension Workflow {
    /// Icon for a workflow-level or object-level row: `<uid>` artwork, then the
    /// workflow icon, then the configured symbol.
    public func resolvedIcon(objectUID: String? = nil) -> WorkflowIconRef {
        WorkflowIcon.resolve(
            path: "",
            workflowRoot: rootPath,
            workflowSymbol: symbol,
            objectUID: objectUID
        )
    }
}

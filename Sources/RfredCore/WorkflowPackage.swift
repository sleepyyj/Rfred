import Foundation

/// Validation and extraction for `.alfredworkflow` zip archives.
/// Callers choose the destination directory (tests use a temp folder;
/// the app copies into Application Support/RfredLocal/ImportedWorkflows).
public enum WorkflowPackage: Sendable {
    public enum ImportError: Error, Equatable, Sendable {
        case missingFile
        case unreadableArchive
        case tooManyMembers
        case unsafePath
        case extractFailed
        case missingInfoPlist

        public var errorDescription: String {
            switch self {
            case .missingFile: "The file could not be found."
            case .unreadableArchive: "The file is not a readable .alfredworkflow archive."
            case .tooManyMembers: "The archive has too many entries to import safely."
            case .unsafePath: "The archive contains unsafe file paths and was not imported."
            case .extractFailed: "The archive could not be extracted."
            case .missingInfoPlist: "The archive does not contain an Alfred info.plist."
            }
        }
    }

    public struct ImportedPackage: Equatable, Sendable {
        public var destination: URL
        public var bundleID: String
        public var name: String
    }

    public static func isImportableFile(_ url: URL) -> Bool {
        let name = url.lastPathComponent.lowercased()
        if name.hasSuffix(".alfredworkflow") { return true }
        if name.hasSuffix(".alfredworkflow.zip") { return true }
        return false
    }

    /// Validates zip-slip / size rules, extracts `url` into `destination`, and
    /// flattens a single top-level folder so `info.plist` sits at the root.
    public static func extract(from url: URL, to destination: URL) -> Result<ImportedPackage, ImportError> {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return .failure(.missingFile) }
        guard let members = archiveMembers(url) else { return .failure(.unreadableArchive) }
        guard members.count <= 20_000 else { return .failure(.tooManyMembers) }
        for member in members {
            let name = String(member)
            if name.hasPrefix("/") || name.split(separator: "/").contains("..") {
                return .failure(.unsafePath)
            }
        }

        try? fm.removeItem(at: destination)
        do {
            try fm.createDirectory(at: destination, withIntermediateDirectories: true)
        } catch {
            return .failure(.extractFailed)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", url.path, destination.path]
        do { try process.run() } catch { return .failure(.extractFailed) }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            try? fm.removeItem(at: destination)
            return .failure(.extractFailed)
        }

        guard let infoURL = locateInfoPlist(in: destination) else {
            try? fm.removeItem(at: destination)
            return .failure(.missingInfoPlist)
        }
        let packageRoot = infoURL.deletingLastPathComponent()
        if packageRoot.standardizedFileURL != destination.standardizedFileURL {
            if !flattenExtractedPackage(from: packageRoot, to: destination) {
                try? fm.removeItem(at: destination)
                return .failure(.extractFailed)
            }
        }

        let info = plist(at: destination.appendingPathComponent("info.plist"))
        let name = string(info?["name"]).flatMap { $0.isEmpty ? nil : $0 }
        let bundleID = string(info?["bundleid"]).flatMap { $0.isEmpty ? nil : $0 }
            ?? name
            ?? destination.lastPathComponent
        let displayName = name ?? bundleID
        return .success(ImportedPackage(destination: destination, bundleID: bundleID, name: displayName))
    }

    private static func archiveMembers(_ url: URL) -> [Substring]? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-Z1", url.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0, let text = String(data: data, encoding: .utf8) else { return nil }
        return text.split(separator: "\n", omittingEmptySubsequences: true)
    }

    private static func locateInfoPlist(in destination: URL) -> URL? {
        let fm = FileManager.default
        let direct = destination.appendingPathComponent("info.plist")
        if fm.fileExists(atPath: direct.path) { return direct }

        let entries = (try? fm.contentsOfDirectory(at: destination, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
        let visible = entries.filter { $0.lastPathComponent != "__MACOSX" }
        if visible.count == 1 {
            var isDirectory: ObjCBool = false
            if fm.fileExists(atPath: visible[0].path, isDirectory: &isDirectory), isDirectory.boolValue {
                let nested = visible[0].appendingPathComponent("info.plist")
                if fm.fileExists(atPath: nested.path) { return nested }
            }
        }
        return nil
    }

    private static func flattenExtractedPackage(from nested: URL, to destination: URL) -> Bool {
        let fm = FileManager.default
        let staging = destination.deletingLastPathComponent().appendingPathComponent(".\(UUID().uuidString)", isDirectory: true)
        do {
            try fm.moveItem(at: nested, to: staging)
            try fm.removeItem(at: destination)
            try fm.moveItem(at: staging, to: destination)
            return true
        } catch {
            try? fm.removeItem(at: staging)
            return false
        }
    }

    private static func plist(at url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url),
              let object = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) else { return nil }
        return object as? [String: Any]
    }

    private static func string(_ value: Any?) -> String? {
        if let text = value as? String { return text }
        if let number = value as? NSNumber { return number.stringValue }
        return nil
    }
}

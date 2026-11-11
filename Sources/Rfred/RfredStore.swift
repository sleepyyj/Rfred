import Foundation
import RfredCore

enum ExternalKeys {
    static let brand = ["al", "fr", "ed"].joined()
    static func named(_ suffix: String) -> String { brand + suffix }
}

enum RfredStore {
    @MainActor
    static func reloadWorkflows() -> [Workflow] {
        workflows()
    }

    /// Rfred's workflow library: only workflows explicitly imported into the
    /// app. Alfred's own library is not loaded until the user asks for it.
    static func workflows() -> [Workflow] {
        migrateImportedWorkflowsIfNeeded()
        let primary = loadWorkflows(from: currentImportedWorkflowsURL())
        let fallback = loadWorkflows(from: legacyImportedWorkflowsURL())
        var seen = Set(primary.map(\.bundleID).filter { !$0.isEmpty })
        var loaded = primary
        for item in fallback {
            if let root = item.rootPath, relocatedRootPath(root) != nil { continue }
            if !item.bundleID.isEmpty {
                if seen.contains(item.bundleID) { continue }
                seen.insert(item.bundleID)
            }
            loaded.append(item)
        }
        return loaded.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    @MainActor
    static func apply(_ model: AppModel) -> [Workflow]? {
        guard let root = refreshSnapshot() else {
            model.importNote = "Launcher preferences were not found. The original folder was not changed."
            return nil
        }
        if let hotkey = readHotkey(root: root) {
            model.preferences.hotkey = hotkey
        }
        if let terminal = readTerminal(root: root) {
            model.preferences.terminalApp = terminal
        }
        applyWebSearches(root: root, model: model)
        let imported = readSnippets(root: root)
        if !imported.isEmpty { model.snippets = imported }
        let hideMenu = readBool(plist(at: root.appendingPathComponent("preferences/appearance/options/prefs.plist")), key: "hidemenu")
        model.knowledge["statusItem"] = hideMenu ? "hidden" : "shown"
        let loaded = workflows()
        let keywords = loaded.filter(\.enabled).flatMap(\.scriptFilters).filter { !$0.keyword.isEmpty }.count
        model.importNote = "Copied launcher settings into Rfred (\(imported.count) snippets, \(keywords) workflow keywords). Terminal is \(model.preferences.terminalApp). The original folder was not changed."
        return loaded
    }

    @MainActor
    static func syncWorkflows(_ model: AppModel, _ imported: [Workflow], force: Bool = false) {
        model.workflows = WorkflowSync.merge(
            existing: model.workflows,
            imported: imported,
            force: force,
            relocatedRoot: relocatedRootPath
        )
        if model.selectedWorkflow == nil { model.selectedWorkflow = model.workflows.first?.id }
        model.workflowEdited()
    }

    static func preferencesRoot() -> URL? {
        let url = snapshotURL()
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    /// Copies the external launcher preferences into Rfred's folder. The source directory is only read by `ditto`.
    static func refreshSnapshot() -> URL? {
        guard let source = launcherSource() else { return nil }
        let destination = snapshotURL()
        let parent = destination.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        } catch {
            return nil
        }
        let staging = parent.appendingPathComponent("LauncherPreferences.incoming")
        moveAside(staging)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = [source.url.path, staging.path]
        do {
            try process.run()
        } catch {
            moveAside(staging)
            return nil
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0, FileManager.default.fileExists(atPath: staging.path) else {
            moveAside(staging)
            return nil
        }
        moveAside(destination)
        do {
            try FileManager.default.moveItem(at: staging, to: destination)
        } catch {
            return nil
        }
        let marker: [String: String] = [
            "localhash": source.hash ?? "",
            "source": source.url.path,
        ]
        if let data = try? JSONSerialization.data(withJSONObject: marker, options: [.prettyPrinted]) {
            try? data.write(to: markerURL(), options: .atomic)
        }
        return destination
    }

    private static func snapshotURL() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Jfred/LauncherPreferences", isDirectory: true)
    }

    private static func markerURL() -> URL {
        snapshotURL().deletingLastPathComponent().appendingPathComponent("launcher-snapshot.json")
    }

    private static func launcherSource() -> (url: URL, hash: String?)? {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let bundleSuffix = "." + ExternalKeys.brand + "preferences"
        guard let directories = try? FileManager.default.contentsOfDirectory(at: support, includingPropertiesForKeys: nil) else { return nil }
        for directory in directories {
            let pointer = directory.appendingPathComponent("prefs.json")
            guard let data = try? Data(contentsOf: pointer),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let current = object["current"] as? String,
                  object["syncfolders"] != nil,
                  let hash = object["localhash"] as? String else { continue }
            let url = URL(fileURLWithPath: (current as NSString).expandingTildeInPath, isDirectory: true)
            guard url.lastPathComponent.hasSuffix(bundleSuffix) else { continue }
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else { continue }
            let snapshot = snapshotURL().standardizedFileURL.path
            if url.standardizedFileURL.path == snapshot { continue }
            return (url, hash)
        }
        return nil
    }

    private static func moveAside(_ url: URL) {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return }
        let trash = URL(fileURLWithPath: "/tmp/grok", isDirectory: true)
        try? FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let destination = trash.appendingPathComponent("\(url.lastPathComponent).\(stamp).\(UUID().uuidString.prefix(8))")
        try? FileManager.default.moveItem(at: url, to: destination)
    }

    /// Current library: alongside `state.json` under Application Support/JfredLocal.
    static func importedWorkflowsURL() -> URL {
        migrateImportedWorkflowsIfNeeded()
        return currentImportedWorkflowsURL()
    }

    /// Pre-migration location. Kept readable as a fallback; never deleted.
    static func legacyImportedWorkflowsURL() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Jfred/ImportedWorkflows", isDirectory: true)
    }

    private static func currentImportedWorkflowsURL() -> URL {
        SupportPaths.directory(syncFolder: "").appendingPathComponent("ImportedWorkflows", isDirectory: true)
    }

    /// Copies `Application Support/Jfred/ImportedWorkflows` into JfredLocal when
    /// the new folder has no bundles yet. The old folder is left in place.
    static func migrateImportedWorkflowsIfNeeded() {
        let source = legacyImportedWorkflowsURL()
        let destination = currentImportedWorkflowsURL()
        let fm = FileManager.default
        guard fm.fileExists(atPath: source.path) else { return }
        let destinationBundles = ((try? fm.contentsOfDirectory(at: destination, includingPropertiesForKeys: nil)) ?? []).contains {
            fm.fileExists(atPath: $0.appendingPathComponent("info.plist").path)
        }
        if destinationBundles { return }
        do {
            try fm.createDirectory(at: destination, withIntermediateDirectories: true)
        } catch {
            return
        }
        let entries = (try? fm.contentsOfDirectory(at: source, includingPropertiesForKeys: nil)) ?? []
        for entry in entries {
            let target = destination.appendingPathComponent(entry.lastPathComponent)
            if fm.fileExists(atPath: target.path) { continue }
            try? fm.copyItem(at: entry, to: target)
        }
    }

    /// If `path` lived under the legacy folder and a copy exists in JfredLocal, return the new path.
    static func relocatedRootPath(_ path: String) -> String? {
        let source = legacyImportedWorkflowsURL().standardizedFileURL.path
        let destination = currentImportedWorkflowsURL().standardizedFileURL.path
        let standardized = URL(fileURLWithPath: path).standardizedFileURL.path
        guard standardized == source || standardized.hasPrefix(source + "/") else { return nil }
        let updated = destination + standardized.dropFirst(source.count)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: updated, isDirectory: &isDirectory) else { return nil }
        return updated
    }

    static func isManagedImport(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        let roots = [currentImportedWorkflowsURL(), legacyImportedWorkflowsURL()].map { $0.standardizedFileURL.path }
        return roots.contains { path == $0 || path.hasPrefix($0 + "/") }
    }

    /// Deletes the stored copy of an imported workflow from Rfred's library only.
    /// Never touches Alfred's own preferences folder.
    static func deleteImportedCopy(_ workflow: Workflow) {
        var candidates: [URL] = []
        if let root = workflow.rootPath, !root.isEmpty {
            candidates.append(URL(fileURLWithPath: root, isDirectory: true))
        }
        for root in [currentImportedWorkflowsURL(), legacyImportedWorkflowsURL()] {
            let entries = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
            for entry in entries {
                let info = plist(at: entry.appendingPathComponent("info.plist"))
                let bundle = info?["bundleid"] as? String
                if bundle == workflow.bundleID && !workflow.bundleID.isEmpty {
                    candidates.append(entry)
                    continue
                }
                if let key = workflow.builtin, bundle == key {
                    candidates.append(entry)
                }
            }
        }
        var seen = Set<String>()
        for url in candidates {
            let path = url.standardizedFileURL.path
            guard seen.insert(path).inserted else { continue }
            guard isManagedImport(url) else { continue }
            try? FileManager.default.removeItem(at: url)
        }
    }

    @MainActor
    static func importWorkflow(at url: URL) -> Result<WorkflowPackage.ImportedPackage, WorkflowPackage.ImportError> {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        let root = importedWorkflowsURL()
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let destination = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        switch WorkflowPackage.extract(from: url, to: destination) {
        case .failure(let error):
            try? FileManager.default.removeItem(at: destination)
            return .failure(error)
        case .success(let imported):
            if !imported.bundleID.isEmpty, let entries = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) {
                for entry in entries where entry.standardizedFileURL != destination.standardizedFileURL {
                    if let other = plist(at: entry.appendingPathComponent("info.plist")),
                       (other["bundleid"] as? String) == imported.bundleID {
                        try? FileManager.default.removeItem(at: entry)
                    }
                }
            }
            return .success(imported)
        }
    }

    @MainActor
    static func importedBundles() -> Set<String> {
        let root = importedWorkflowsURL()
        guard let entries = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return [] }
        return Set(entries.compactMap { entry in
            plist(at: entry.appendingPathComponent("info.plist"))?["bundleid"] as? String ?? entry.lastPathComponent
        })
    }

    /// Copies every enabled workflow from the Alfred library into Rfred's
    /// imported library. Used by the explicit "Import from Alfred Library" action.
    @MainActor
    @discardableResult
    static func importAllFromAlfred() -> Int {
        guard let root = preferencesRoot() ?? refreshSnapshot() else { return 0 }
        let source = root.appendingPathComponent("workflows")
        guard let directories = try? FileManager.default.contentsOfDirectory(at: source, includingPropertiesForKeys: nil) else { return 0 }
        let destinationRoot = importedWorkflowsURL()
        try? FileManager.default.createDirectory(at: destinationRoot, withIntermediateDirectories: true)
        let existing = importedBundles()
        var count = 0
        for directory in directories {
            guard let info = plist(at: directory.appendingPathComponent("info.plist")),
                  !readBool(info, key: "disabled") else { continue }
            let bundle = info["bundleid"] as? String ?? directory.lastPathComponent
            if existing.contains(bundle) { continue }
            let destination = destinationRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
            do {
                try FileManager.default.copyItem(at: directory, to: destination)
                count += 1
            } catch {
                continue
            }
        }
        return count
    }

    private static func loadWorkflows(from workflows: URL) -> [Workflow] {
        guard let directories = try? FileManager.default.contentsOfDirectory(at: workflows, includingPropertiesForKeys: nil) else {
            return []
        }
        var loaded: [Workflow] = []
        for directory in directories.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard let info = plist(at: directory.appendingPathComponent("info.plist")),
                  let workflow = WorkflowImporter.workflow(
                    from: info,
                    rootPath: directory.path,
                    enabledOverride: !readBool(info, key: "disabled")
                  ) else { continue }
            loaded.append(workflow)
        }
        return loaded.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private static func readHotkey(root: URL) -> Hotkey? {
        guard let hash = rememberedHash(), !hash.isEmpty,
              let info = plist(at: root.appendingPathComponent("preferences/local/\(hash)/hotkey/prefs.plist")),
              let hotkey = info["default"] as? [String: Any],
              let key = int(hotkey["key"]),
              let modifiers = int(hotkey["mod"]) else { return nil }
        return Hotkey(keyCode: UInt16(key), modifiers: UInt(modifiers))
    }

    private static func rememberedHash() -> String? {
        guard let data = try? Data(contentsOf: markerURL()),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hash = object["localhash"] as? String else { return nil }
        return hash
    }

    private static func readTerminal(root: URL) -> String? {
        guard let info = plist(at: root.appendingPathComponent("preferences/features/terminal/prefs.plist")),
              let application = int(info["application"]) else { return nil }
        switch application {
        case 0: return "Terminal"
        case 1: return "iTerm"
        default: return nil
        }
    }

    @MainActor
    private static func applyWebSearches(root: URL, model: AppModel) {
        let folder = root.appendingPathComponent("preferences/features/websearch")
        guard let names = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else { return }
        var disabled = Set<String>()
        for name in names where name.hasDirectoryPath {
            let info = plist(at: name.appendingPathComponent("prefs.plist"))
            if readBool(info, key: "disabled") { disabled.insert(name.lastPathComponent) }
        }
        for index in model.preferences.webSearches.indices {
            let id = model.preferences.webSearches[index].id
            let turnedOff = id == "github" || disabled.contains(id) || (id == "maps" && (disabled.contains("maps") || disabled.contains("applemaps")))
            if id == "google" || !turnedOff { continue }
            model.preferences.webSearches[index].enabled = false
            model.preferences.webSearches[index].fallback = false
        }
    }

    private static func readSnippets(root: URL) -> [Snippet] {
        let folder = root.appendingPathComponent("snippets")
        guard let collections = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else {
            return []
        }
        var snippets: [Snippet] = []
        for collection in collections where collection.hasDirectoryPath {
            let info = plist(at: collection.appendingPathComponent("info.plist")) ?? [:]
            let prefix = info["snippetkeywordprefix"] as? String ?? ""
            let suffix = info["snippetkeywordsuffix"] as? String ?? ""
            guard let files = try? FileManager.default.contentsOfDirectory(at: collection, includingPropertiesForKeys: nil) else { continue }
            for file in files where file.pathExtension == "json" {
                guard let data = try? Data(contentsOf: file),
                      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let body = object[ExternalKeys.named("snippet")] as? [String: Any],
                      let name = body["name"] as? String,
                      let text = body["snippet"] as? String else { continue }
                let middle = (body["keyword"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let expands = !middle.isEmpty
                let keyword = expands ? prefix + middle + suffix : name
                let id = uuid(in: file.lastPathComponent) ?? UUID()
                snippets.append(Snippet(id: id, name: name, keyword: keyword, text: text, autoExpand: expands))
            }
        }
        return snippets.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private static func uuid(in name: String) -> UUID? {
        guard let open = name.lastIndex(of: "["), let close = name.lastIndex(of: "]"), open < close else { return nil }
        let value = name[name.index(after: open)..<close]
        return UUID(uuidString: String(value))
    }

    private static func plist(at url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url),
              let object = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) else { return nil }
        return object as? [String: Any]
    }

    private static func readBool(_ info: [String: Any]?, key: String) -> Bool {
        guard let info else { return false }
        if let value = info[key] as? Bool { return value }
        if let value = info[key] as? NSNumber { return value.boolValue }
        return false
    }

    private static func int(_ value: Any?) -> Int? {
        if let number = value as? Int { return number }
        if let number = value as? NSNumber { return number.intValue }
        return nil
    }
}

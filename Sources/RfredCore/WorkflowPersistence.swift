import Foundation

/// Merge and persistence helpers for imported workflows. Kept in RfredCore so
/// the additive-sync and lossy-decode behaviour can be unit tested.
public enum WorkflowSync {
    public static let legacyBuiltinKeys: Set<String> = [
        "dev", "epoch", "unit", "kill", "tabs", "profiles", "windows", "ui",
    ]

    /// Obsolete built-in placeholders have a legacy key and no stored bundle.
    /// User-imported workflows with a real `rootPath` or a distinct bundle ID
    /// are never treated as placeholders.
    public static func isLegacyPlaceholder(_ workflow: Workflow) -> Bool {
        guard let key = workflow.builtin, legacyBuiltinKeys.contains(key) else { return false }
        if let root = workflow.rootPath, !root.isEmpty { return false }
        if !workflow.bundleID.isEmpty, workflow.bundleID != key { return false }
        return true
    }

    public static func matchIndex(in workflows: [Workflow], imported: Workflow) -> Int? {
        if !imported.bundleID.isEmpty {
            if let index = workflows.firstIndex(where: { $0.builtin == imported.bundleID || $0.bundleID == imported.bundleID }) {
                return index
            }
        }
        if let root = imported.rootPath, !root.isEmpty {
            return workflows.firstIndex(where: { $0.rootPath == root })
        }
        return nil
    }

    /// Additive merge used by startup sync and Reload Workflows.
    /// New bundles from the on-disk scan are inserted or refreshed; existing
    /// user-imported or user-created items are kept even if the scan missed them.
    public static func merge(
        existing: [Workflow],
        imported: [Workflow],
        force: Bool = false,
        relocatedRoot: ((String) -> String?)? = nil
    ) -> [Workflow] {
        var workflows = existing.filter { !isLegacyPlaceholder($0) }
        if let relocatedRoot {
            for index in workflows.indices {
                if let root = workflows[index].rootPath, let updated = relocatedRoot(root) {
                    workflows[index].rootPath = updated
                }
            }
        }
        for item in imported {
            if let index = matchIndex(in: workflows, imported: item) {
                let current = workflows[index]
                var merged = item
                merged.id = current.id
                merged.enabled = current.enabled && item.enabled
                merged.hotkey = current.hotkey
                if !force, !current.objects.isEmpty,
                   current.definitionVersion >= item.definitionVersion,
                   current.version == item.version {
                    if let root = item.rootPath, root != current.rootPath {
                        workflows[index].rootPath = root
                    }
                    continue
                }
                if current.symbol != "puzzlepiece.extension" { merged.symbol = current.symbol }
                if current.tint != WorkflowImporter.tint(for: item.bundleID) { merged.tint = current.tint }
                workflows[index] = merged
            } else {
                workflows.append(item)
            }
        }
        return workflows
    }
}

public extension Workflow {
    /// True when this workflow was imported (it has a bundle id, builtin key,
    /// or stored root) but the bundle folder is missing on disk.
    var isMissingBundle: Bool {
        let imported = builtin != nil || !bundleID.isEmpty || (rootPath?.isEmpty == false)
        guard imported else { return false }
        guard let rootPath, !rootPath.isEmpty else { return true }
        var isDirectory: ObjCBool = false
        return !FileManager.default.fileExists(atPath: rootPath, isDirectory: &isDirectory)
    }
}

/// Decodes an array, skipping individual elements that fail instead of failing
/// the whole container.
public struct LossyDecodableArray<Element: Decodable>: Decodable {
    public var elements: [Element]
    public var skippedIndexes: [Int]

    public init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var elements: [Element] = []
        var skipped: [Int] = []
        var index = 0
        while !container.isAtEnd {
            do {
                elements.append(try container.decode(Element.self))
            } catch {
                skipped.append(index)
                // A failed decode does not advance the unkeyed container.
                _ = try container.decode(AnyDecodableJSON.self)
            }
            index += 1
        }
        self.elements = elements
        self.skippedIndexes = skipped
    }
}

public enum StateFile {
    public static func isPlausible(_ data: Data) -> Bool {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        return object["preferences"] != nil && object["workflows"] != nil
    }

    public static func isDegraded(newWorkflowCount: Int, previous: Data?) -> Bool {
        guard let previous,
              let object = try? JSONSerialization.jsonObject(with: previous) as? [String: Any],
              let workflows = object["workflows"] as? [Any],
              !workflows.isEmpty else { return false }
        return newWorkflowCount == 0
    }

    /// Replace the last good `state.json.bak` only when the file being
    /// overwritten is itself a plausible, non-degraded snapshot.
    public static func shouldUpdateBackup(current: Data?, newWorkflowCount: Int, allowed: Bool) -> Bool {
        guard allowed, let current, isPlausible(current), !isDegraded(newWorkflowCount: newWorkflowCount, previous: current) else {
            return false
        }
        return true
    }
}

/// Consumes one JSON value of any shape so a skipped array element is not retried.
struct AnyDecodableJSON: Decodable {
    init(from decoder: Decoder) throws {
        if var array = try? decoder.unkeyedContainer() {
            while !array.isAtEnd {
                _ = try array.decode(AnyDecodableJSON.self)
            }
            return
        }
        if let object = try? decoder.container(keyedBy: AnyJSONKey.self) {
            for key in object.allKeys {
                _ = try object.decode(AnyDecodableJSON.self, forKey: key)
            }
            return
        }
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { return }
        if (try? container.decode(Bool.self)) != nil { return }
        if (try? container.decode(Int.self)) != nil { return }
        if (try? container.decode(Double.self)) != nil { return }
        _ = try? container.decode(String.self)
    }
}

private struct AnyJSONKey: CodingKey {
    var stringValue: String
    var intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = Int(stringValue)
    }

    init?(intValue: Int) {
        self.intValue = intValue
        self.stringValue = String(intValue)
    }
}

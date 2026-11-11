import Foundation

public final class ProcessWorkflowRunner: WorkflowScriptRunning, @unchecked Sendable {
    public init() {}

    public func run(_ request: WorkflowScriptRequest) async -> WorkflowScriptOutput {
        await Task.detached(priority: .userInitiated) {
            Self.execute(request)
        }.value
    }

    private static func execute(_ request: WorkflowScriptRequest) -> WorkflowScriptOutput {
        let fileManager = FileManager.default
        let cache = request.environment["alfred_workflow_cache"].map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? fileManager.temporaryDirectory.appendingPathComponent("RfredWorkflowCache", isDirectory: true)
        let data = request.environment["alfred_workflow_data"].map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? fileManager.temporaryDirectory.appendingPathComponent("RfredWorkflowData", isDirectory: true)
        try? fileManager.createDirectory(at: cache, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: data, withIntermediateDirectories: true)

        var temporaryScript: URL?
        defer {
            if let temporaryScript { try? fileManager.removeItem(at: temporaryScript) }
        }

        let executable: String
        var arguments: [String] = []
        if !request.sourceFile.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            var path = (request.sourceFile as NSString).expandingTildeInPath
            if !path.hasPrefix("/") {
                path = request.directory.appendingPathComponent(path).path
            }
            guard fileManager.fileExists(atPath: path) else {
                return WorkflowScriptOutput(error: "Script file not found: \(path)")
            }
            let resolved = executableForScriptFile(path, language: request.language)
            executable = resolved.executable
            if resolved.executable == path {
                arguments = request.arguments
            } else {
                arguments = resolved.arguments + [path] + request.arguments
            }
        } else {
            let source = request.source
            guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return WorkflowScriptOutput(error: "Script is empty")
            }
            let suffix = fileSuffix(for: request.language)
            let url = cache.appendingPathComponent("rfred-\(request.objectID.uuidString)-\(UUID().uuidString).\(suffix)")
            do {
                try source.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                return WorkflowScriptOutput(error: "Could not stage script: \(error.localizedDescription)")
            }
            temporaryScript = url
            switch request.language {
            case .external:
                if source.hasPrefix("#!") {
                    try? fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
                    executable = url.path
                } else {
                    executable = "/bin/bash"
                    arguments = [url.path]
                }
            case .osascript:
                executable = "/usr/bin/osascript"
                arguments = [url.path]
            case .swift:
                executable = "/usr/bin/swift"
                arguments = [url.path]
            case .php:
                executable = "/usr/bin/php"
                arguments = [url.path]
            case .ruby:
                executable = "/usr/bin/ruby"
                arguments = [url.path]
            case .python:
                let python3 = "/usr/bin/python3"
                executable = fileManager.isExecutableFile(atPath: python3) ? python3 : "/usr/bin/python"
                arguments = [url.path]
            case .perl:
                executable = "/usr/bin/perl"
                arguments = [url.path]
            case .bash:
                executable = "/bin/bash"
                arguments = [url.path]
            case .zsh:
                executable = "/bin/zsh"
                arguments = [url.path]
            }
        }
        if request.sourceFile.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            arguments += request.arguments
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = request.directory
        process.environment = request.environment
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        let outBuffer = PipeBuffer()
        let errBuffer = PipeBuffer()
        stdout.fileHandleForReading.readabilityHandler = { handle in
            outBuffer.append(handle.availableData)
        }
        stderr.fileHandleForReading.readabilityHandler = { handle in
            errBuffer.append(handle.availableData)
        }
        let group = DispatchGroup()
        group.enter()
        process.terminationHandler = { _ in group.leave() }
        do {
            try process.run()
        } catch {
            stdout.fileHandleForReading.readabilityHandler = nil
            stderr.fileHandleForReading.readabilityHandler = nil
            group.leave()
            return WorkflowScriptOutput(error: "Could not launch \(executable): \(error.localizedDescription)")
        }
        var timedOut = false
        if group.wait(timeout: .now() + 20) == .timedOut {
            timedOut = true
            process.terminate()
            _ = group.wait(timeout: .now() + 1)
        }
        stdout.fileHandleForReading.readabilityHandler = nil
        stderr.fileHandleForReading.readabilityHandler = nil
        outBuffer.append(stdout.fileHandleForReading.readDataToEndOfFile())
        errBuffer.append(stderr.fileHandleForReading.readDataToEndOfFile())
        let status = timedOut ? -1 : process.terminationStatus
        return WorkflowScriptOutput(
            stdout: outBuffer.text,
            stderr: errBuffer.text,
            status: status,
            error: timedOut ? "Script timed out after 20 seconds" : nil
        )
    }

    private static func executableForScriptFile(_ path: String, language: WorkflowScriptLanguage) -> (executable: String, arguments: [String]) {
        if FileManager.default.isExecutableFile(atPath: path) {
            if let first = try? String(contentsOfFile: path, encoding: .utf8).split(separator: "\n", maxSplits: 1).first,
               first.hasPrefix("#!") {
                return (path, [])
            }
        }
        switch language {
        case .bash, .external: return ("/bin/bash", [])
        case .zsh: return ("/bin/zsh", [])
        case .php: return ("/usr/bin/php", [])
        case .ruby: return ("/usr/bin/ruby", [])
        case .python: return ("/usr/bin/python3", [])
        case .perl: return ("/usr/bin/perl", [])
        case .osascript: return ("/usr/bin/osascript", [])
        case .swift: return ("/usr/bin/swift", [])
        }
    }

    private static func fileSuffix(for language: WorkflowScriptLanguage) -> String {
        switch language {
        case .bash: return "sh"
        case .zsh: return "zsh"
        case .php: return "php"
        case .ruby: return "rb"
        case .python: return "py"
        case .perl: return "pl"
        case .osascript: return "applescript"
        case .swift: return "swift"
        case .external: return "sh"
        }
    }
}

private final class PipeBuffer: @unchecked Sendable {
    private var data = Data()
    private let lock = NSLock()

    func append(_ chunk: Data) {
        guard !chunk.isEmpty else { return }
        lock.lock()
        if data.count < 2_000_000 { data.append(chunk) }
        lock.unlock()
    }

    var text: String {
        lock.lock()
        defer { lock.unlock() }
        return String(data: data, encoding: .utf8) ?? ""
    }
}

import Foundation

public enum ProjectOperationError: Error, Equatable, LocalizedError {
    case invalidName(String)
    case destinationExists(String)
    case cloneFailed(String)
    case initFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidName(let name) where name.isEmpty:
            return "The folder name is empty."
        case .invalidName(let name):
            return "“\(name)” can't be used as a folder name. Names can't be “.” or “..” and can't contain “/” or “:”."
        case .destinationExists(let path):
            return "\(path) already exists. Choose another name or location."
        case .cloneFailed(let message):
            return "git clone failed: \(message)"
        case .initFailed(let message):
            return "git init failed: \(message)"
        }
    }
}

/// The launcher's two writes: a new local project and a clone. Neither touches a folder that already exists.
public enum ProjectOperations {
    static let projectMap = "# PROJECT_MAP\n\n## TECH_STACK\n\n## SYSTEM_FLOW\n\n## ORPHANS & PENDING\n"

    public static func createProject(named name: String, in parent: URL, runner: CommandRunner = ProcessRunner()) async throws -> URL {
        let folder = try destination(named: name.trimmingCharacters(in: .whitespacesAndNewlines), in: parent)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        } catch {
            throw ProjectOperationError.initFailed(error.localizedDescription)
        }
        do {
            let result = try await runner.run("git", ["init"], in: folder, timeout: CommandTimeout.git)
            guard result.succeeded else {
                let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                throw ProjectOperationError.initFailed(stderr.isEmpty ? "git exited with status \(result.status)" : stderr)
            }
            try projectMap.write(to: folder.appendingPathComponent("PROJECT_MAP.md"), atomically: true, encoding: .utf8)
        } catch {
            try? FileManager.default.removeItem(at: folder)
            if error is CancellationError || error is ProjectOperationError { throw error }
            throw ProjectOperationError.initFailed(error.localizedDescription)
        }
        return folder
    }

    public static func cloneRepository(url: String, into parent: URL, runner: CommandRunner = ProcessRunner()) async throws -> URL {
        let source = url.trimmingCharacters(in: .whitespacesAndNewlines)
        let folder = try destination(named: folderName(fromCloneURL: source), in: parent)
        let result: CommandResult
        do {
            result = try await runner.run("git", ["clone", "--", source, folder.path], in: parent, timeout: CommandTimeout.clone)
        } catch let cancellation as CancellationError {
            throw cancellation
        } catch {
            throw ProjectOperationError.cloneFailed(error.localizedDescription)
        }
        guard result.succeeded else {
            throw ProjectOperationError.cloneFailed(GitOutput.lastNonEmptyLine(result.stderr) ?? "git exited with status \(result.status)")
        }
        return folder
    }

    /// The last path component of a clone URL, without a trailing "/" or ".git"; "host:repo" forms split on the colon.
    static func folderName(fromCloneURL url: String) -> String {
        var value = url.trimmingCharacters(in: .whitespacesAndNewlines)
        while value.hasSuffix("/") { value.removeLast() }
        if value.hasSuffix(".git") { value.removeLast(4) }
        if let separator = value.lastIndex(where: { $0 == "/" || $0 == ":" }) {
            value = String(value[value.index(after: separator)...])
        }
        return value
    }

    private static func destination(named name: String, in parent: URL) throws -> URL {
        guard !name.isEmpty, name != ".", name != "..", !name.contains("/"), !name.contains(":") else {
            throw ProjectOperationError.invalidName(name)
        }
        let folder = parent.appendingPathComponent(name, isDirectory: false)
        guard !FileManager.default.fileExists(atPath: folder.path) else { throw ProjectOperationError.destinationExists(folder.path) }
        return folder
    }
}

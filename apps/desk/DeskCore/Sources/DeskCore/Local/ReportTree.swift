import Foundation

/// The reports a folder holds across everywhere they can be: the checkout on disk, origin's base, and branches that
/// hold nothing but a report. A report is read where it is, through git, so what Findings shows no longer depends on
/// which branch happens to be checked out. The first place a name is found in wins: the checkout (it may be newer
/// than anything committed), then the base, then report branches.
struct ReportTree {
    let root: URL
    let runner: CommandRunner
    let maxBytes: Int

    /// One folder's reports, name → contents, in the precedence above.
    func reports(in folder: String, toplevel: URL, refs: [String]) async -> [String: SafeFile.Read] {
        var found: [String: SafeFile.Read] = [:]
        let directory = toplevel.appendingPathComponent(folder)
        for name in ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []) where name.hasSuffix(".md") {
            found[name] = SafeFile.read(directory.appendingPathComponent(name), maxBytes: maxBytes, within: toplevel)
        }
        for ref in refs {
            for entry in await entries(ref: ref, folder: folder) where found[entry.name] == nil {
                found[entry.name] = entry.size > maxBytes ? .tooLarge : await blob(entry.object)
            }
        }
        return found
    }

    struct Entry: Equatable {
        let name: String
        let object: String
        let size: Int
    }

    /// `ls-tree -z -l <ref> -- <folder>/`: "<mode> blob <object> <size>\t<path>" per entry; only the folder's own
    /// Markdown files, never a subfolder, a symlink or a submodule.
    static func entries(_ output: String) -> [Entry] {
        output.components(separatedBy: "\0").compactMap { record in
            guard let tab = record.firstIndex(of: "\t") else { return nil }
            let fields = record[..<tab].split(separator: " ", omittingEmptySubsequences: true)
            let path = String(record[record.index(after: tab)...])
            guard fields.count == 4, fields[0] == "100644" || fields[0] == "100755", fields[1] == "blob",
                  let size = Int(fields[3]) else { return nil }
            let name = (path as NSString).lastPathComponent
            guard name.hasSuffix(".md") else { return nil }
            return Entry(name: name, object: String(fields[2]), size: size)
        }
    }

    private func entries(ref: String, folder: String) async -> [Entry] {
        guard !ref.hasPrefix("-"),
              let result = try? await runner.run("git", GitCommand.read(["ls-tree", "-z", "-l", ref, "--", "\(folder)/"]),
                                                 in: root, timeout: CommandTimeout.git),
              result.succeeded else { return [] }
        return Self.entries(result.stdout)
    }

    private func blob(_ object: String) async -> SafeFile.Read {
        guard object.allSatisfy(\.isHexDigit),
              let result = try? await runner.run("git", GitCommand.read(["cat-file", "blob", object]), in: root, timeout: CommandTimeout.git),
              result.succeeded else { return .skipped }
        return result.stdout.utf8.count > maxBytes ? .tooLarge : .text(result.stdout)
    }
}

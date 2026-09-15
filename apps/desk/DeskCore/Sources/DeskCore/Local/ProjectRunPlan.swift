import Foundation

/// One way of running the project itself — `cd web && npm run dev` — as the project's own file says it.
/// Rows run in order in the same shell and stop at the first failure, so a row is a line and never a script.
public struct ProjectRunConfiguration: Codable, Equatable, Identifiable, Sendable {
    /// Generated once when the configuration is added and never derived from the name: the toolbar's live
    /// run and the session it opened are keyed by this, and a rename must not orphan a running one.
    public var id: String
    public var name: String
    public var commands: [String]
    /// Runs before Dev Desk stops this run. Empty means the foreground job is interrupted instead.
    public var stop: [String]
    public var isDefault: Bool

    public init(id: String = ProjectRunConfiguration.newID(), name: String, commands: [String] = [],
                stop: [String] = [], isDefault: Bool = false) {
        self.id = id
        self.name = name
        self.commands = commands
        self.stop = stop
        self.isDefault = isDefault
    }

    /// Short, lower-case and unguessable enough: the file is committed and read by people, so a whole UUID
    /// per configuration is noise, and eight hex characters do not collide inside one project's list.
    public static func newID() -> String {
        String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(8).lowercased())
    }

    private enum CodingKeys: String, CodingKey { case id, name, commands, stop, isDefault }

    /// A hand-edited file leaves keys out; each one has an obvious absence, so none is an error.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? Self.newID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        commands = try container.decodeIfPresent([String].self, forKey: .commands) ?? []
        stop = try container.decodeIfPresent([String].self, forKey: .stop) ?? []
        isDefault = try container.decodeIfPresent(Bool.self, forKey: .isDefault) ?? false
    }
}

/// What `.devdesk/run.json` holds: the setup rows and the named configurations. The plan is the project's,
/// committed beside its code, so every clone and every worktree runs it the same way.
public struct ProjectRunPlan: Codable, Equatable, Sendable {
    /// Written so a later shape can tell an older file apart; an unknown value is still read as this one,
    /// because refusing a file over its version number would discard settings the user can see are fine.
    public static let version = 1

    /// Rows that run once, the first time Dev Desk runs the project in a folder — installs, mostly.
    public var setup: [String]
    public var configurations: [ProjectRunConfiguration]

    public init(setup: [String] = [], configurations: [ProjectRunConfiguration] = []) {
        self.setup = setup
        self.configurations = configurations
    }

    public static let empty = ProjectRunPlan()

    public var isEmpty: Bool { setup.isEmpty && configurations.isEmpty }

    private enum CodingKeys: String, CodingKey { case version, setup, configurations }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        setup = try container.decodeIfPresent([String].self, forKey: .setup) ?? []
        configurations = try container.decodeIfPresent([ProjectRunConfiguration].self, forKey: .configurations) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.version, forKey: .version)
        try container.encode(setup, forKey: .setup)
        try container.encode(configurations, forKey: .configurations)
    }

    public func configuration(id: String) -> ProjectRunConfiguration? {
        configurations.first { $0.id == id }
    }

    /// The one the toolbar's play button runs: the first marked default, else the first there is. A file
    /// with no mark still has a default, because a play button that does nothing until a checkbox is found
    /// is a play button nobody presses twice.
    public var defaultConfiguration: ProjectRunConfiguration? {
        configurations.first { $0.isDefault } ?? configurations.first
    }

    /// The plan as it is saved: blank rows gone, names trimmed, exactly one default. Read and save both
    /// pass through here, so what the toolbar offers and what the file says never disagree.
    public func normalised() -> ProjectRunPlan {
        var plan = ProjectRunPlan(setup: Self.cleanRows(setup),
                                  configurations: configurations.map { configuration in
            var cleaned = configuration
            cleaned.name = configuration.name.trimmingCharacters(in: .whitespacesAndNewlines)
            cleaned.commands = Self.cleanRows(configuration.commands)
            cleaned.stop = Self.cleanRows(configuration.stop)
            return cleaned
        })
        guard let chosen = plan.defaultConfiguration else { return plan }
        for index in plan.configurations.indices {
            plan.configurations[index].isDefault = plan.configurations[index].id == chosen.id
        }
        return plan
    }

    /// Trimmed rows with the blank ones dropped: an empty row is a field the user has not filled in yet,
    /// never a command.
    public static func cleanRows(_ rows: [String]) -> [String] {
        rows.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    /// The rows as one line for the shell — `a && b && c` — which is what "in order, in the same shell, and
    /// stop at the first failure" means to a shell. Nil when there is nothing to run, so the caller opens no
    /// session for it.
    public static func shellLine(rows: [String]) -> String? {
        let cleaned = cleanRows(rows)
        return cleaned.isEmpty ? nil : cleaned.joined(separator: " && ")
    }

    /// The line a run of `configuration` types into its shell; the setup rows lead when they are included.
    public func shellLine(configuration: ProjectRunConfiguration, includingSetup: Bool) -> String? {
        Self.shellLine(rows: (includingSetup ? setup : []) + configuration.commands)
    }

    /// The line typed to stop a run gracefully, or nil when the configuration has no stop rows.
    public func stopLine(configuration: ProjectRunConfiguration) -> String? {
        Self.shellLine(rows: configuration.stop)
    }
}

/// `.devdesk/run.json` on disk: read through the same bounded, symlink-refusing path every other repo file
/// takes, and written atomically so a half-saved file never reaches git.
public enum ProjectRunFile {
    public static let relativePath = ".devdesk/run.json"
    /// Far above any plan a person writes, and far below anything that could stall the app while it is read.
    public static let maxBytes = 256 * 1024

    public enum Read: Equatable {
        /// No file: the project has never been configured, which is not an error.
        case missing
        case plan(ProjectRunPlan)
        /// A file that exists and could not be used, with the reason a pane can show. The distinction from
        /// `missing` is the whole point: a plan the app could not read must not be replaced by an empty one.
        case unreadable(String)

        /// What the app runs with: an empty plan for anything but a readable file.
        public var plan: ProjectRunPlan {
            if case .plan(let plan) = self { return plan }
            return .empty
        }

        public var error: String? {
            if case .unreadable(let reason) = self { return reason }
            return nil
        }
    }

    public static func url(in projectRoot: URL) -> URL {
        projectRoot.appendingPathComponent(relativePath)
    }

    public static func read(projectRoot: URL) -> Read {
        let url = url(in: projectRoot)
        // lstat rather than fileExists, which follows a symlink and would call a dangling one missing.
        var info = stat()
        guard lstat(url.path, &info) == 0 else { return .missing }
        switch SafeFile.read(url, maxBytes: maxBytes, within: projectRoot) {
        case .text(let text): return parse(text)
        case .tooLarge: return .unreadable("\(relativePath) is larger than \(maxBytes / 1024) KB, so it was not read.")
        case .hardLink: return .unreadable("\(relativePath) is a hard link, so it was not read.")
        case .skipped: return .unreadable("\(relativePath) is not a regular file inside the project — a symlink, or one that could not be opened — so it was not read.")
        }
    }

    /// The plan in `text`, normalised, or why it is not one.
    public static func parse(_ text: String) -> Read {
        do {
            let plan = try JSONDecoder().decode(ProjectRunPlan.self, from: Data(text.utf8))
            return .plan(plan.normalised())
        } catch {
            return .unreadable("\(relativePath) is not valid JSON for a run plan: \(Self.describe(error))")
        }
    }

    /// Pretty and sorted: the file is committed, and a save that reorders keys is a diff nobody asked for.
    public static func encode(_ plan: ProjectRunPlan) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        var data = try encoder.encode(plan.normalised())
        data.append(0x0A)
        return data
    }

    /// Creates `.devdesk/` when the project has none yet. Atomic, so git never sees a partial file.
    public static func write(_ plan: ProjectRunPlan, projectRoot: URL) throws {
        let url = url(in: projectRoot)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encode(plan).write(to: url, options: .atomic)
    }

    /// Foundation's decoding errors name a coding path and a debug description; the path is what the person
    /// editing the file needs and the description is what they would search for.
    private static func describe(_ error: Error) -> String {
        guard let decoding = error as? DecodingError else { return error.localizedDescription }
        switch decoding {
        case .dataCorrupted(let context): return context.debugDescription
        case .keyNotFound(let key, _): return "missing key \"\(key.stringValue)\""
        case .typeMismatch(_, let context), .valueNotFound(_, let context):
            let path = context.codingPath.map(\.stringValue).joined(separator: ".")
            return path.isEmpty ? context.debugDescription : "\(path): \(context.debugDescription)"
        @unknown default: return decoding.localizedDescription
        }
    }
}

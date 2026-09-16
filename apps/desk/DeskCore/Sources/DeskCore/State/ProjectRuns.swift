import Foundation
import Observation

/// Which rows a run should type: the plain run, setup forced in front of it, or the setup rows alone.
public enum ProjectRunIntent: Equatable, Sendable {
    case run, setupAndRun, setupOnly
}

/// Everything the app needs to open a run's session, decided here so the decision is testable without a
/// shell: which session, what it is called, and the one line typed into it.
public struct ProjectRunLaunch: Equatable, Sendable {
    public let sessionID: String
    /// Nil for setup alone, which belongs to no configuration.
    public let configuration: ProjectRunConfiguration?
    public var title: String
    public let shellLine: String
    /// Whether the setup rows lead the line — what the marker file records once the run is dispatched.
    public let includesSetup: Bool
}

/// The machine-local record of where Dev Desk has run setup: `.devdesk/run-state.json`, a map of folder path
/// to the moment setup was dispatched there. It is honest about what it records — that Dev Desk *started*
/// the setup rows in that folder, not that they succeeded — which is why the menu always offers to run them
/// again, and why nothing here is ever read as "this folder is ready".
struct ProjectRunState: Codable, Equatable {
    static let relativePath = ".devdesk/run-state.json"
    var setupStarted: [String: Date] = [:]

    static func url(in projectRoot: URL) -> URL { projectRoot.appendingPathComponent(relativePath) }

    /// A missing or unreadable marker means "no setup has been recorded", which is also the safe reading:
    /// it costs one extra install, never a skipped one.
    static func read(projectRoot: URL) -> ProjectRunState {
        guard let data = try? Data(contentsOf: url(in: projectRoot)),
              let state = try? decoder.decode(ProjectRunState.self, from: data) else { return ProjectRunState() }
        return state
    }

    /// Bookkeeping beside a real run: a full disk must not stop the run it is describing, so this never throws.
    func write(projectRoot: URL) {
        guard let data = try? Self.encoder.encode(self) else { return }
        let url = Self.url(in: projectRoot)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

/// This window's way of running the project itself: the plan read from `.devdesk/run.json`, the run that is
/// live, and the decisions around both. The shell and the terminal stay in the app layer — this class says
/// *what* to type and *where*, and is tested with a folder rather than a process.
@MainActor
@Observable
public final class ProjectRuns {
    /// A distinct prefix from a scratch terminal's `term:`, so the Sessions screen can tell a run's row apart.
    public static let sessionPrefix = "run:"
    /// The session setup runs in on its own. `#` is never in a generated id, so no configuration can claim it.
    public static let setupSessionID = "run:#setup"

    public static func sessionID(configurationID: String) -> String { sessionPrefix + configurationID }
    public static func isRunSession(_ id: String) -> Bool { id.hasPrefix(sessionPrefix) }

    /// The plan as last read or saved; empty for a sample, which has no folder to hold one.
    public private(set) var plan: ProjectRunPlan = .empty
    /// Why the file could not be read, when it exists and could not be. Nil is "no file" as much as "read fine".
    public private(set) var readError: String?
    /// Run sessions this window has opened, oldest first, live or ended — the Sessions screen's rows. A
    /// session stays listed after its shell exits, the way a door's does, until it is taken off the list.
    public private(set) var sessionIDs: [String] = []
    /// What each run session was called when it started: the plan may have renamed or deleted its
    /// configuration since, and the row must still say what ran.
    public private(set) var sessionTitles: [String: String] = [:]
    /// The configuration behind each live run's session, kept so stopping it can find its stop rows even
    /// after the plan has been edited under it.
    @ObservationIgnored private var sessionConfigurations: [String: ProjectRunConfiguration] = [:]
    /// The folder each run session runs in — the project folder, or a worktree.
    public private(set) var sessionFolders: [String: String] = [:]

    @ObservationIgnored public let projectRoot: URL?
    @ObservationIgnored private let sessions: ShellSessions

    /// A nil root, as a sample has, leaves the plan empty and every launch nil.
    public init(projectRoot: URL?, sessions: ShellSessions) {
        self.projectRoot = projectRoot
        self.sessions = sessions
        reload()
    }

    // MARK: - The plan

    /// Reads the file again. An unreadable file leaves an empty plan and the reason; nothing is written.
    public func reload() {
        guard let projectRoot else {
            plan = .empty
            readError = nil
            return
        }
        let read = ProjectRunFile.read(projectRoot: projectRoot)
        plan = read.plan
        readError = read.error
    }

    /// Writes the plan and keeps it. This is the only path that touches the file, and it runs only on the
    /// user's own edit — which is what lets the pane promise never to overwrite a file it could not parse.
    public func save(_ plan: ProjectRunPlan) throws {
        guard let projectRoot else { return }
        try ProjectRunFile.write(plan, projectRoot: projectRoot)
        self.plan = plan.normalised()
        readError = nil
    }

    public var canRun: Bool { projectRoot != nil && !plan.configurations.isEmpty }

    // MARK: - The live run

    public func isRunning(configurationID: String) -> Bool {
        sessions.state(for: Self.sessionID(configurationID: configurationID)).isLive
    }

    public func isLive(sessionID: String) -> Bool { sessions.state(for: sessionID).isLive }

    /// The configuration whose run is live, read from the session rather than remembered: a shell that
    /// exited on its own ends the run whether or not anything here was told.
    public var liveConfiguration: ProjectRunConfiguration? {
        for id in sessionIDs where isLive(sessionID: id) {
            if let configuration = sessionConfigurations[id] { return configuration }
        }
        return nil
    }

    /// The session of the live run, configuration or setup, or nil when nothing runs.
    public var liveSessionID: String? {
        sessionIDs.first { isLive(sessionID: $0) }
    }

    public var isAnythingRunning: Bool { liveSessionID != nil }

    /// The live run of `configurationID` (nil = the default), with the folder it runs in.
    public func liveRun(configurationID: String?) -> (sessionID: String, folderPath: String?)? {
        guard let configuration = configurationID.map(plan.configuration(id:)) ?? plan.defaultConfiguration else { return nil }
        let id = Self.sessionID(configurationID: configuration.id)
        return isLive(sessionID: id) ? (id, sessionFolders[id]) : nil
    }

    /// The stop rows for a live session, as one line, or nil when its configuration has none.
    public func stopLine(sessionID: String) -> String? {
        guard let configuration = sessionConfigurations[sessionID] else { return nil }
        return plan.stopLine(configuration: configuration)
    }

    /// A session's row title, or the id when this window never started it.
    public func title(sessionID: String) -> String { sessionTitles[sessionID] ?? sessionID }

    // MARK: - Setup

    /// Whether a run in `folderPath` should lead with the setup rows: yes the first time Dev Desk runs the
    /// project there, no afterwards. A plan with no setup rows never needs them.
    public func needsSetup(in folderPath: String) -> Bool {
        guard let projectRoot, !plan.setup.isEmpty else { return false }
        return ProjectRunState.read(projectRoot: projectRoot).setupStarted[folderPath] == nil
    }

    /// Records that setup was dispatched in `folderPath` — started, not finished (see `ProjectRunState`).
    public func markSetupStarted(in folderPath: String, at date: Date = Date()) {
        guard let projectRoot else { return }
        var state = ProjectRunState.read(projectRoot: projectRoot)
        state.setupStarted[folderPath] = date
        state.write(projectRoot: projectRoot)
    }

    // MARK: - Launching

    /// What to open for `configurationID` (nil picks the default) under `intent`, in `folderPath`, or nil
    /// when there is nothing to run: a sample, an unknown configuration, empty rows, or a run already live
    /// for that configuration. Decides only — `dispatched` records it once the session really started.
    public func prepare(configurationID: String? = nil, intent: ProjectRunIntent = .run, folderPath: String) -> ProjectRunLaunch? {
        guard projectRoot != nil else { return nil }
        if intent == .setupOnly {
            guard let line = ProjectRunPlan.shellLine(rows: plan.setup), !isLive(sessionID: Self.setupSessionID) else { return nil }
            return ProjectRunLaunch(sessionID: Self.setupSessionID, configuration: nil, title: "Run · Setup",
                                    shellLine: line, includesSetup: true)
        }
        // A named configuration that is not in the plan is nothing, not the default: the menu item that named
        // it was built from an older plan, and running something else under its name would be a surprise.
        guard let configuration = configurationID.map(plan.configuration(id:)) ?? plan.defaultConfiguration,
              !isRunning(configurationID: configuration.id) else { return nil }
        let includesSetup = !plan.setup.isEmpty && (intent == .setupAndRun || needsSetup(in: folderPath))
        guard let line = plan.shellLine(configuration: configuration, includingSetup: includesSetup) else { return nil }
        return ProjectRunLaunch(sessionID: Self.sessionID(configurationID: configuration.id), configuration: configuration,
                                title: "Run · \(configuration.name.isEmpty ? configuration.id : configuration.name)",
                                shellLine: line, includesSetup: includesSetup)
    }

    /// The session for `launch` is running: list it, and record the setup as started where it ran.
    public func dispatched(_ launch: ProjectRunLaunch, in folderPath: String) {
        if !sessionIDs.contains(launch.sessionID) { sessionIDs.append(launch.sessionID) }
        sessionTitles[launch.sessionID] = launch.title
        sessionConfigurations[launch.sessionID] = launch.configuration
        sessionFolders[launch.sessionID] = folderPath
        if launch.includesSetup { markSetupStarted(in: folderPath) }
    }

    /// Takes an ended run off the list. A live one stays: closing its row would orphan the process behind it.
    public func forget(sessionID: String) {
        guard !isLive(sessionID: sessionID) else { return }
        sessionIDs.removeAll { $0 == sessionID }
        sessionTitles[sessionID] = nil
        sessionConfigurations[sessionID] = nil
        sessionFolders[sessionID] = nil
    }
}

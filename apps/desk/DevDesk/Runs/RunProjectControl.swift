import DeskCore
import SwiftUI

extension ProjectWindowModel {
    /// The project folder, on whatever branch it is on — what the toolbar's play runs.
    var projectFolderTarget: RunTarget? {
        guard let root = projectRoot else { return nil }
        return RunTarget(folder: root, branch: snapshot?.project.branch ?? RunTarget.branch(in: root), isProjectFolder: true)
    }

    /// What play and ⌘R run: the worktree the toolbar's picker has chosen, which is also the one Files shows.
    /// It followed the session in front on the Terminals tab, so the folder a run went to changed with the tab
    /// you happened to be on; the picker says it outright now, beside play rather than inside its label.
    var runTarget: RunTarget? {
        guard let root = projectFolderTarget else { return nil }
        guard let path = filesWorktreePath else { return root }
        let folder = URL(fileURLWithPath: path, isDirectory: true)
        let branch = filesWorktrees.first { $0.path == path }?.branch ?? RunTarget.branch(in: folder)
        return RunTarget(folder: folder, branch: branch, isProjectFolder: false)
    }

    /// A worktree as the picker names it: its branch, or its folder when it has none (a detached HEAD).
    func worktreeLabel(_ worktree: Worktree) -> String {
        worktree.branch ?? "\(URL(fileURLWithPath: worktree.path).lastPathComponent) (detached)"
    }

    /// The chosen worktree's name, for the picker and the Files header.
    var chosenWorktreeLabel: String {
        let chosen = filesWorktrees.first { worktree in
            isProjectFolder(worktree) ? filesWorktreePath == nil : worktree.path == filesWorktreePath
        }
        return chosen.map(worktreeLabel) ?? snapshot?.project.branch ?? filesRoot?.lastPathComponent ?? ""
    }

    /// A press of play, for `target`. One live run per configuration across every folder: the same folder shows
    /// the run already going, another folder asks first, because both would want the same port.
    func requestProjectRun(configurationID: String? = nil, intent: ProjectRunIntent = .run, target: RunTarget,
                           terminals: ShellTerminalRegistry, worktreeLocation: String) {
        if intent != .setupOnly, let live = projectRuns.liveRun(configurationID: configurationID) {
            if live.folderPath.map({ URL(fileURLWithPath: $0).standardizedFileURL }) == target.folder.standardizedFileURL {
                selectedSessionID = live.sessionID
                go(.terminals)
            } else {
                let configuration = configurationID.map(projectRuns.plan.configuration(id:)) ?? projectRuns.plan.defaultConfiguration
                pendingRunReplacement = RunReplacement(
                    configurationID: configurationID, intent: intent, folderPath: target.folder.path, branch: target.branch,
                    liveSessionID: live.sessionID,
                    liveBranch: live.folderPath.map { RunTarget.branch(in: URL(fileURLWithPath: $0, isDirectory: true)) } ?? "another folder",
                    configurationName: configuration?.name ?? "The run")
            }
            return
        }
        startProjectRun(configurationID: configurationID, intent: intent, target: target, terminals: terminals,
                        worktreeLocation: worktreeLocation)
    }

    /// "Stop it and run here": the live run ends first — its port has to be free — then this one starts.
    func confirmRunReplacement(terminals: ShellTerminalRegistry, worktreeLocation: String) {
        guard let replacement = pendingRunReplacement else { return }
        pendingRunReplacement = nil
        stopProjectRun(sessionID: replacement.liveSessionID, terminals: terminals)
        let folder = URL(fileURLWithPath: replacement.folderPath, isDirectory: true)
        let target = RunTarget(folder: folder, branch: replacement.branch, isProjectFolder: folder.standardizedFileURL == projectRoot?.standardizedFileURL)
        Task {
            for _ in 0..<40 where projectRuns.isLive(sessionID: replacement.liveSessionID) {
                try? await Task.sleep(for: .milliseconds(250))
            }
            startProjectRun(configurationID: replacement.configurationID, intent: replacement.intent, target: target,
                            terminals: terminals, worktreeLocation: worktreeLocation)
        }
    }

    /// Starts a run of the project in a session of its own — `run:<configuration id>` — in `target`'s folder, with
    /// the plan's line typed into the shell the way a door's command is. The shell opens at the project root and
    /// moves into a worktree before the line, and the run's title names the branch it runs.
    func startProjectRun(configurationID: String? = nil, intent: ProjectRunIntent = .run, target: RunTarget? = nil,
                         terminals: ShellTerminalRegistry, worktreeLocation: String) {
        guard let root = projectRoot, let target = target ?? projectFolderTarget else { return }
        guard var launch = projectRuns.prepare(configurationID: configurationID, intent: intent, folderPath: target.folder.path) else {
            if let id = configurationID.map(ProjectRuns.sessionID(configurationID:)) ?? projectRuns.liveSessionID,
               projectRuns.isLive(sessionID: id) {
                selectedSessionID = id
                go(.terminals)
            }
            return
        }
        launch.title += " · \(target.branch)"
        // Land on the run, the way every other start does: its output is the point of pressing play.
        selectedSessionID = launch.sessionID
        go(.terminals)
        let id = launch.sessionID
        let line = target.folder.standardizedFileURL == root.standardizedFileURL
            ? launch.shellLine : "cd \(ShellQuote.single(target.folder.path)) && " + launch.shellLine
        Task {
            await sessions.start(taskID: id, branch: nil, taskNumber: nil, noBranchNote: nil,
                                 worktreeLocation: worktreeLocation, title: launch.title)
            guard case .running(let folder) = sessions.state(for: id) else { return }
            // Recorded where the run really goes, which is what the setup marker is keyed by.
            projectRuns.dispatched(launch, in: target.isProjectFolder ? folder.url.path : target.folder.path)
            terminals.start(taskID: id, folder: folder.url)
            terminals.send(line + "\n", to: id)
        }
    }

    /// Stops a live run. The run is the shell's foreground job, so the stop rows cannot reach a prompt until
    /// it has been interrupted: ^C first — at a prompt that is already free it costs nothing — then the stop
    /// rows, given a moment, then the session's own end, whose SIGHUP and SIGKILL reach the shell's process
    /// group. A tree that survives that — an orphaned worker, a port still held — is a job for the family's
    /// own door, `/dev:launch-kill`, which proves ownership by cwd before it kills; Dev Desk does not
    /// reimplement that.
    func stopProjectRun(sessionID: String, terminals: ShellTerminalRegistry) {
        guard projectRuns.isLive(sessionID: sessionID) else { return }
        let stopLine = projectRuns.stopLine(sessionID: sessionID)
        Task {
            terminals.send("\u{03}", to: sessionID)
            try? await Task.sleep(for: .milliseconds(400))
            if let stopLine {
                terminals.send(stopLine + "\n", to: sessionID)
                try? await Task.sleep(for: .seconds(3))
            }
            terminals.end(taskID: sessionID)
        }
    }
}

/// The toolbar's play/stop for the project itself: play runs the default configuration, stop ends the live
/// one, and the chevron beside it lists every configuration, the two setup actions and the editor.
struct RunProjectControl: View {
    let model: ProjectWindowModel
    let terminals: ShellTerminalRegistry?
    @AppStorage(PreferenceKey.worktreeLocation) private var worktreeLocation = AgentDefaults.worktreeLocation
    @Environment(\.deskWindowSize) private var windowSize

    private var runs: ProjectRuns { model.projectRuns }
    private var liveSessionID: String? { runs.liveSessionID }
    private var isRunning: Bool { liveSessionID != nil }
    private var isSample: Bool { model.projectRoot == nil }
    private var hasSetup: Bool { !runs.plan.setup.isEmpty }

    /// What the live run is called in the control: its configuration's name, or the session's own title
    /// for setup alone, which belongs to no configuration.
    private var liveName: String {
        if let configuration = runs.liveConfiguration { return configuration.name }
        return liveSessionID.map { runs.title(sessionID: $0) } ?? ""
    }

    static let sampleReason = "A sample has no folder to run, so there is nothing to start."
    static let nothingConfiguredReason = "Nothing is configured yet. Add a run configuration in Settings → Run project."

    /// Why play cannot start anything, or nil when it can. Stop is never blocked: what is live can end.
    private var blockedReason: String? {
        if isSample { return Self.sampleReason }
        if runs.plan.configurations.isEmpty { return Self.nothingConfiguredReason }
        if terminals == nil { return "This window cannot start a session." }
        return nil
    }

    /// The name earns its place only where the toolbar has room for it; below the rail breakpoint the
    /// sidebar itself has already given up its labels.
    private var isWide: Bool { windowSize.width >= DeskMetric.railBreakpoint }

    /// Where a press of play runs: the worktree picker's choice, the same folder ⌘R runs (ADR 0053).
    private var target: RunTarget? { model.runTarget }

    var body: some View {
        HStack(spacing: 2) {
            Button(action: primaryAction) { primaryLabel }
                .disabled(!isRunning && blockedReason != nil)
                .help(primaryHelp)
                .accessibilityLabel(isRunning ? "Stop \(liveName)" : "Run project")
                .accessibilityValue(isRunning ? "Running" : "Stopped")
            Menu { menuItems } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(isSample ? DeskColor.disabledDot : DeskColor.navInk)
                    .frame(width: 14, height: 20)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .disabled(isSample)
            .help(isSample ? Self.sampleReason : "Choose a configuration, run setup, or edit the configurations")
            .accessibilityLabel("Run project options")
        }
    }

    private var primaryLabel: some View {
        HStack(spacing: 6) {
            Image(systemName: isRunning ? "stop.fill" : "play.fill")
                .imageScale(.medium)
                .foregroundStyle(isRunning ? DeskColor.tone(.running).dot : DeskColor.navInk)
            if isRunning {
                StatusDot(tone: .running, pulses: true)
                if isWide {
                    Text(liveName)
                        .font(DeskFont.secondary)
                        .foregroundStyle(DeskColor.navInk)
                        .lineLimit(1)
                        .frame(maxWidth: 160)
                }
            }
        }
    }

    private var primaryHelp: String {
        if isRunning { return "Stop \(liveName)" }
        if let blockedReason { return blockedReason }
        let name = runs.plan.defaultConfiguration?.name ?? ""
        guard let target else { return "Run \(name)" }
        let place = target.isProjectFolder ? "the project folder" : "the \(target.branch) worktree"
        return "Run \(name) in \(place) — \(target.folder.path)"
    }

    private func primaryAction() {
        guard let terminals else { return }
        if let liveSessionID {
            model.stopProjectRun(sessionID: liveSessionID, terminals: terminals)
        } else {
            guard let target else { return }
            model.requestProjectRun(target: target, terminals: terminals, worktreeLocation: worktreeLocation)
        }
    }

    private func run(_ configurationID: String?, intent: ProjectRunIntent = .run, in override: RunTarget? = nil) {
        guard let terminals else { return }
        guard let target = override ?? target else { return }
        model.requestProjectRun(configurationID: configurationID, intent: intent, target: target, terminals: terminals,
                                worktreeLocation: worktreeLocation)
    }

    @ViewBuilder private var menuItems: some View {
        ForEach(runs.plan.configurations) { configuration in
            let isLive = runs.isRunning(configurationID: configuration.id)
            Button { run(configuration.id) } label: {
                if isLive {
                    Label(configuration.name, systemImage: "checkmark")
                } else {
                    Text(configuration.name)
                }
            }
            .help(isLive ? "Shows the live run of \(configuration.name)" : "Runs \(configuration.name) in a terminal at the project root")
        }
        if !runs.plan.configurations.isEmpty { Divider() }
        Button("Setup and run") { run(nil, intent: .setupAndRun) }
            .disabled(!hasSetup || runs.plan.configurations.isEmpty || isRunning)
            .help(hasSetup ? "Runs the setup rows first, then the default configuration, whether or not setup has run here before"
                           : "No setup rows are configured")
        Button("Setup only") { run(nil, intent: .setupOnly) }
            .disabled(!hasSetup)
            .help(hasSetup ? "Runs the setup rows alone in a terminal at the project root" : "No setup rows are configured")
        Divider()
        Button("Edit configurations…") {
            model.settingsSection = .runProject
            model.present(.settings)
        }
        .help("Opens Settings → Run project, where the setup rows and the configurations live")
    }
}

/// Which checkout the project is working in — the project folder or one of its worktrees, named by branch. Its own
/// control, beside play rather than inside its label: choosing a folder is not running it. Files shows the same
/// choice, and play runs in it.
struct WorktreePicker: View {
    let model: ProjectWindowModel
    @Environment(\.deskWindowSize) private var windowSize

    private var isSample: Bool { model.projectRoot == nil }
    /// A new card's worktree appears in `git worktree list` when its checkout does, so the list is read again then.
    private var listKey: String { model.ref.id + "|" + model.tasks.compactMap(\.checkoutPath).sorted().joined(separator: "|") }

    var body: some View {
        Menu {
            ForEach(model.filesWorktrees, id: \.path) { worktree in
                let tag = model.isProjectFolder(worktree) ? nil : worktree.path
                Button { model.filesWorktreePath = tag } label: {
                    let name = model.worktreeLabel(worktree) + (tag == nil ? " — the project folder" : "")
                    if tag == model.filesWorktreePath { Label(name, systemImage: "checkmark") } else { Text(name) }
                }
                .help(worktree.path)
            }
            Divider()
            Button("Refresh List") { Task { await model.loadFilesWorktrees() } }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "arrow.trianglehead.branch").font(.system(size: 10))
                if windowSize.width >= DeskMetric.railBreakpoint {
                    Text(model.chosenWorktreeLabel).lineLimit(1).truncationMode(.middle).frame(maxWidth: 160)
                }
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
            }
            .font(DeskFont.secondary)
            .foregroundStyle(model.filesWorktreePath == nil ? DeskColor.mutedInk : DeskColor.navInk)
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(isSample)
        .help(isSample ? RunProjectControl.sampleReason : "The checkout Files shows and play runs in — \(model.filesRoot?.path ?? "")")
        .accessibilityLabel("Worktree")
        .accessibilityValue(model.chosenWorktreeLabel)
        .task(id: listKey) { await model.loadFilesWorktrees() }
    }
}

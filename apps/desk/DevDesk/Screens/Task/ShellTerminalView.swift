import AppKit
import DeskCore
import SwiftTerm
import SwiftUI

/// A task's live shell in the dock. The terminal view belongs to the window's registry and is only re-parented here, so rebuilding the pane never restarts the shell.
struct ShellTerminalView: NSViewRepresentable {
    let terminals: ShellTerminalRegistry
    let taskID: String
    @AppStorage(PreferenceKey.terminalFontSize) private var fontSize = 12.0

    func makeNSView(context: Context) -> ShellTerminalHost { ShellTerminalHost() }

    func updateNSView(_ host: ShellTerminalHost, context: Context) {
        let terminal = terminals.view(for: taskID)
        if terminal.font.pointSize != fontSize {
            terminal.font = .monospacedSystemFont(ofSize: fontSize, weight: .regular)
        }
        host.show(terminal)
    }

    /// A newer pane may already have taken the terminal; only a view still hosted here is let go.
    static func dismantleNSView(_ host: ShellTerminalHost, coordinator: ()) {
        host.subviews.forEach { $0.removeFromSuperview() }
    }
}

/// Holds the registry's terminal as its only subview, taking it from whichever pane showed it last. It also makes a click on the terminal
/// reliably give it focus, since SwiftTerm's own mouseDown only selects.
final class ShellTerminalHost: NSView {
    private var clickMonitor: LocalEventMonitor?
    private var scrollMonitor: LocalEventMonitor?

    func show(_ terminal: NSView) {
        guard terminal.superview !== self else { return }
        subviews.forEach { $0.removeFromSuperview() }
        // A host SwiftUI has just made has no size yet. Sizing the terminal to that told the program inside its
        // window was a row or two, and a full-screen agent (opencode, claude) redrew for it, then again at full
        // size into a buffer the shrink had already cut — the pane came back as scattered fragments on every tab
        // switch. So the terminal keeps its last size until the host has a real one (`layout`).
        terminal.autoresizingMask = []
        if !bounds.isEmpty { terminal.frame = bounds }
        addSubview(terminal)
        terminal.needsDisplay = true
        // Re-parenting into a dialog leaves first responder wherever it was — on the sheet's buttons, which
        // then take ↑/↓ before the terminal sees them. A terminal that has just appeared is the thing being
        // looked at, so it asks for focus again.
        if let focusing = terminal as? FocusingTerminalView {
            focusing.focusOnAttach = true
            focusing.takeFocusIfAsked()
        }
    }

    /// The one place the terminal takes the host's size, and only a real one — never the empty frame of a host
    /// that has not been laid out yet.
    override func layout() {
        super.layout()
        guard !bounds.isEmpty, let terminal = subviews.first, terminal.frame != bounds else { return }
        terminal.frame = bounds
    }

    /// The app's events reach a local monitor before any view, so this holds whatever SwiftUI draws around the terminal.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        clickMonitor = window == nil ? nil : LocalEventMonitor([.leftMouseDown, .rightMouseDown]) { [weak self] event in
            self?.focusTerminal(clickedBy: event)
        }
        scrollMonitor = window == nil ? nil : LocalEventMonitor(filtering: .scrollWheel) { [weak self] event in
            guard let self, let window, event.window === window, let terminal = subviews.first as? FocusingTerminalView,
                  let hit = (window.contentView?.superview ?? window.contentView)?.hitTest(event.locationInWindow),
                  hit === terminal || hit.isDescendant(of: terminal) else { return event }
            return terminal.forwardScroll(event) ? nil : event
        }
    }

    private func focusTerminal(clickedBy event: NSEvent) {
        guard let window, event.window === window, let terminal = subviews.first, window.firstResponder !== terminal,
              let hit = (window.contentView?.superview ?? window.contentView)?.hitTest(event.locationInWindow),
              hit === terminal || hit.isDescendant(of: terminal) else { return }
        window.makeFirstResponder(terminal)
    }
}

/// A local monitor of the app's events, removed when this is released, so the view holding one leaves none behind.
final class LocalEventMonitor {
    private let token: Any?

    init(_ mask: NSEvent.EventTypeMask, handler: @escaping @MainActor (NSEvent) -> Void) {
        token = NSEvent.addLocalMonitorForEvents(matching: mask) { event in
            // Local monitors run on the main thread.
            MainActor.assumeIsolated { handler(event) }
            return event
        }
    }

    /// A monitor that may swallow the event: the handler returns nil for one it has handled.
    init(filtering mask: NSEvent.EventTypeMask, handler: @escaping @MainActor (NSEvent) -> NSEvent?) {
        token = NSEvent.addLocalMonitorForEvents(matching: mask) { event in
            MainActor.assumeIsolated { handler(event) }
        }
    }

    deinit {
        if let token { NSEvent.removeMonitor(token) }
    }
}

/// How an agent start came out, which Auto keeps track of.
enum AgentStart {
    case launched
    /// The folder would have been the project root, which Auto refuses: the session failed with the folder's note.
    case refusedAtRoot
    /// Auto was turned off while the folder was prepared: the session ended without launching anything.
    case cancelled
    /// Another start had the session, or the window closed.
    case skipped
}

/// One window's shells, or its agents, keyed by task id; the window keeps one registry of each, so a task can have both.
/// Each outlives its pane, so switching tasks or hiding the dock keeps it running.
@MainActor
final class ShellTerminalRegistry {
    private let sessions: ShellSessions
    private var terminals: [String: ShellTerminal] = [:]
    /// Set when the window closes, so a start still preparing its folder then launches nothing.
    private(set) var isClosed = false
    /// The program each task's last command ran, which the Agents tab names when the shell couldn't find it.
    private(set) var executables: [String: String] = [:]

    init(sessions: ShellSessions) {
        self.sessions = sessions
    }

    /// The same view on every call until its shell exits; the next start then gets a fresh one rather than the old screen.
    func view(for taskID: String) -> LocalProcessTerminalView {
        terminal(for: taskID).view
    }

    /// Called once the session is running, so the generation read here is the one this process belongs to.
    /// An empty command runs the login shell itself; otherwise the login shell runs the command.
    func start(taskID: String, folder: URL, command: [String] = []) {
        guard !isClosed else { return }
        if let executable = command.first {
            executables[taskID] = executable
            sessions.noteExecutable(executable, for: taskID)
        }
        terminal(for: taskID).executable = command.first
        let terminal = terminal(for: taskID)
        runsCommand[taskID] = !command.isEmpty
        reportsThroughHooks[taskID] = AgentHooks.reports(command.first)
        terminal.start(in: folder, generation: sessions.generation(for: taskID), command: AgentHooks.inject(into: command))
    }

    /// A door's command, typed into its shell with the agent's hooks added. `preamble` (a `cd … && `) goes in front
    /// after the hooks are added: the agent is found by the line starting with it.
    func sendCommand(_ line: String, to taskID: String, preamble: String = "") {
        let executable = line.split(separator: " ").first.map(String.init)
        if AgentHooks.reports(executable) { reportsThroughHooks[taskID] = true }
        if let executable, AgentKind(rawValue: executable) != nil {
            executables[taskID] = executable
            sessions.noteExecutable(executable, for: taskID)
            terminal(for: taskID).executable = executable
        }
        send(preamble + AgentHooks.inject(into: line) + "\n", to: taskID)
    }

    /// What each session reports — a question, a finished turn, its own exit, a bell. Set by the window, which knows
    /// whether the session is on screen.
    var onEvent: ((String, TerminalEvent) -> Void)?
    /// Sessions whose agent is working on a message right now, by its own hooks. A Done task's session waits for
    /// its turn to end before it is closed, so the run's closing report is not cut off.
    private var midTurn: Set<String> = []
    func isMidTurn(_ taskID: String) -> Bool { midTurn.contains(taskID) }
    /// Sessions whose agent reports through hooks: their bell is not also read as a question.
    private var reportsThroughHooks: [String: Bool] = [:]
    /// Sessions started with a command, whose exit is the run ending. A plain shell exiting is the developer typing `exit`.
    private var runsCommand: [String: Bool] = [:]

    /// Prepares the task's folder, then runs the agent there. The start counts towards the app's agents from this call, so Auto's limit
    /// holds while the folder is prepared. Auto passes `refusingRoot`, so a folder that would fall back to the project root fails instead,
    /// and `stillWanted`, read again just before the launch, so turning Auto off meanwhile launches nothing.
    @discardableResult
    func startAgent(for task: DeskTask, agent: AgentKind, worktreeLocation: String, mode: RunMode = .standard,
                    refusingRoot: Bool = false, stillWanted: (() -> Bool)? = nil) -> Task<AgentStart, Never> {
        let live = LiveShells.shared
        live.track(agentSessions: sessions)
        live.agentStartPending()
        let command = Self.command(agent, for: task, mode: mode)
        return Task {
            // Nothing suspends between this and the session's move to preparing, which then holds the place in the count.
            live.agentStartBegan()
            guard !isClosed else { return .skipped }
            let previous = sessions.generation(for: task.id)
            await sessions.start(taskID: task.id, branch: task.branch, taskNumber: task.taskNumber, noBranchNote: task.noBranchNote,
                                 worktreeLocation: worktreeLocation, title: task.title, baseRef: task.baseRef,
                                 refusingRoot: refusingRoot)
            // An unchanged generation means this start ran nothing: another start had the session, or the root was refused.
            guard sessions.generation(for: task.id) != previous, case .running(let folder) = sessions.state(for: task.id) else {
                if refusingRoot, case .failed = sessions.state(for: task.id) { return .refusedAtRoot }
                return .skipped
            }
            if let stillWanted, !stillWanted() {
                sessions.markEnded(taskID: task.id, status: nil, generation: sessions.generation(for: task.id))
                return .cancelled
            }
            guard !isClosed else { return .skipped }
            start(taskID: task.id, folder: folder.url, command: command)
            return .launched
        }
    }

    /// `claude <prompt>` or `codex <prompt>`; a Debug build's `-DevDeskAgentExecutable` stands in for the CLI.
    static func command(_ agent: AgentKind, for task: DeskTask, mode: RunMode = .standard) -> [String] {
        let prompt = AgentLaunch.prompt(skillRoot: AgentLaunch.skillRoot(for: agent), taskNumber: task.taskNumber, hasBranch: !(task.branch ?? "").isEmpty, mode: mode)
        var arguments = AgentLaunch.arguments(agent: agent, prompt: prompt)
        if let executable = DebugLaunch.agentExecutable, !arguments.isEmpty { arguments[0] = executable }
        return arguments
    }

    func end(taskID: String) {
        terminals[taskID]?.end()
    }

    /// Types into a running shell, exactly as the user would; a shell that has not started, or has exited, gets nothing.
    func send(_ text: String, to taskID: String) {
        guard let terminal = terminals[taskID], terminal.isRunning else { return }
        terminal.view.send(txt: text)
    }

    /// The window is closing: ends every process, refuses the starts still preparing their folder, and takes this window's agents out of
    /// the app's count at once, so Auto in other windows can use their places.
    func endAll() {
        isClosed = true
        terminals.values.forEach { $0.end() }
        LiveShells.shared.untrack(agentSessions: sessions)
    }

    private func terminal(for taskID: String) -> ShellTerminal {
        if let terminal = terminals[taskID] { return terminal }
        // The exit carries the generation its process started under, so a late exit can't end a session started
        // after it. The transcript's tail travels with the exit: the terminal is dropped a line below, and a
        // failed headless run's one-line error was being dropped with it.
        let terminal = ShellTerminal { [weak self] terminal, status in
            guard let self else { return }
            midTurn.remove(taskID)
            if runsCommand[taskID] == true, !terminal.wasEnded, let status { onEvent?(taskID, .exited(status)) }
            sessions.markEnded(taskID: taskID, status: status, generation: terminal.generation,
                               outputTail: terminal.transcriptTail())
            if terminals[taskID] === terminal { terminals[taskID] = nil }
        }
        terminal.onEvent = { [weak self] event in
            guard let self else { return }
            switch event {
            case .turnStarted: midTurn.insert(taskID)
            case .turnFinished, .question, .exited: midTurn.remove(taskID)
            case .bell: break
            }
            if event == .bell, reportsThroughHooks[taskID] == true { return }
            onEvent?(taskID, event)
        }
        terminals[taskID] = terminal
        return terminal
    }
}

/// Every live shell and agent in the app, across windows. Holding them here keeps one that is being ended alive until it is gone,
/// and lets quit end them all with one wait of at most 2 s rather than one per window. It also counts the app's agents for Auto.
@MainActor
@Observable
final class LiveShells {
    static let shared = LiveShells()
    @ObservationIgnored private var shells: [ObjectIdentifier: ShellTerminal] = [:]
    @ObservationIgnored private var terminateObserver: NSObjectProtocol?
    /// Each window's agent sessions, held weakly. Observed, so a window that closes changes the count at once.
    private var agentSessions: [WeakSessions] = []
    /// Starts asked for whose session hasn't yet moved to preparing.
    private var pendingAgentStarts = 0

    private init() {
        terminateObserver = NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification,
                                                                   object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { LiveShells.shared.endAllBeforeQuit() }
        }
    }

    /// Agents preparing their folder or running, in every window, plus starts about to prepare: what Auto's limit counts.
    var agentCount: Int {
        pendingAgentStarts + agentSessions.reduce(0) { $0 + ($1.sessions?.activeTaskIDs.count ?? 0) }
    }

    func insert(_ shell: ShellTerminal) { shells[ObjectIdentifier(shell)] = shell }
    func remove(_ shell: ShellTerminal) { shells[ObjectIdentifier(shell)] = nil }

    func track(agentSessions sessions: ShellSessions) {
        guard !agentSessions.contains(where: { $0.sessions === sessions }) else { return }
        agentSessions.removeAll { $0.sessions == nil }
        agentSessions.append(WeakSessions(sessions: sessions))
    }

    /// A closing window's agents leave the count now, rather than whenever its sessions are freed, which nothing would notice.
    func untrack(agentSessions sessions: ShellSessions) {
        guard agentSessions.contains(where: { $0.sessions === sessions }) else { return }
        agentSessions.removeAll { $0.sessions === sessions || $0.sessions == nil }
    }

    func agentStartPending() { pendingAgentStarts += 1 }
    func agentStartBegan() { pendingAgentStarts -= 1 }

    private struct WeakSessions {
        weak var sessions: ShellSessions?
    }

    /// Quit leaves no time for a timer and holds the main queue, so no exit monitor fires: SIGHUP every shell and its job,
    /// reap for at most 2 s in all, then SIGKILL whatever is left.
    func endAllBeforeQuit() {
        // Quitting is the app's own ending, so what was live is marked clean before it goes: only a kill or a
        // crash leaves the records unclean, and that is what the next launch offers to recover (ADR 0031).
        agentSessions.compactMap(\.sessions).forEach { $0.markAllClean() }
        let all = Array(shells.values)
        all.forEach { $0.send(SIGHUP) }
        var waiting = all
        let deadline = Date().addingTimeInterval(2)
        while !waiting.isEmpty, Date() < deadline {
            waiting.removeAll { $0.reap() && !$0.hasLiveJobs }
            if !waiting.isEmpty { usleep(20_000) }
        }
        all.forEach { $0.send(SIGKILL) }
    }
}

/// The user's login shell, which runs every shell and agent so they get the user's PATH.
enum LoginShell {
    /// $SHELL, else /bin/zsh.
    static var path: String {
        ProcessInfo.processInfo.environment["SHELL"].flatMap { $0.isEmpty ? nil : $0 } ?? "/bin/zsh"
    }

    static var name: String { (path as NSString).lastPathComponent }

    /// What follows the shell's path to have it exec `command` as an interactive login shell, so a PATH set in ~/.zshrc applies as well as
    /// one set in ~/.zprofile. Each word stays an argument of its own. Nil for a shell other than zsh, bash or fish.
    static func arguments(running command: [String]) -> [String]? {
        switch name {
        case "zsh", "bash": return ["-l", "-i", "-c", #"exec "$0" "$@""#] + command
        case "fish": return ["-l", "-i", "-c", "exec $argv"] + command
        default: return nil
        }
    }

    static var unsupportedReason: String? {
        arguments(running: []) == nil ? "Dev Desk can start agents through zsh, bash or fish; your login shell is \(name)." : nil
    }
}

/// One task's terminal and the login shell inside it. It is also the process delegate, which SwiftTerm holds only weakly.
@MainActor
final class ShellTerminal: LocalProcessTerminalViewDelegate {
    let view: FocusingTerminalView
    private(set) var hasExited = false
    /// The session's generation when this process started.
    private(set) var generation = 0
    private let onExit: @MainActor (ShellTerminal, Int32?) -> Void
    /// What the session reports about itself: hook events, and the bell.
    var onEvent: (@MainActor (TerminalEvent) -> Void)?
    /// The CLI running in this session, so its events are read the way that CLI reports them.
    var executable: String?
    /// Set by `end()`: a session the developer stopped is not news.
    private(set) var wasEnded = false
    /// The folder this session's hooks drop events into, and the watch on it.
    private var eventDirectory: URL?
    private var eventWatch: DispatchSourceFileSystemObject?
    private var exitMonitor: DispatchSourceProcess?
    /// Foreground job groups seen while signalling; an interactive shell runs each job in a group of its own.
    private var jobGroups: Set<pid_t> = []

    init(onExit: @escaping @MainActor (ShellTerminal, Int32?) -> Void) {
        self.onExit = onExit
        view = FocusingTerminalView(frame: NSRect(x: 0, y: 0, width: 640, height: 240))
        view.nativeBackgroundColor = NSColor(DeskColor.terminalGround)
        view.nativeForegroundColor = NSColor(DeskColor.terminalInk)
        view.caretColor = NSColor(DeskColor.terminalInk)
        // Option types characters, as it does in Terminal by default, rather than acting as Meta.
        view.optionAsMetaKey = false
        view.processDelegate = self
        view.onBell = { [weak self] in self?.onEvent?(.bell) }
        // A sent line is a turn begun in any CLI (AgentProtocol): the CLIs that report it are believed, and the
        // ones that report nothing are covered by this.
        view.onSend = { [weak self] in
            guard let self, executable != nil else { return }
            if let eventDirectory { AgentHooks.markWorking(.turnStarted, in: eventDirectory, protocol: AgentProtocol.of(executable)) }
            onEvent?(.turnStarted)
        }
    }

    var isRunning: Bool { view.process.shellPid != 0 && !hasExited }

    /// True while a job group signalled earlier still has its leader in the shell's session.
    var hasLiveJobs: Bool {
        let pid = view.process.shellPid
        return pid > 0 && jobGroups.contains { getsid($0) == pid }
    }

    /// Runs `$SHELL -l` in `folder` with the user's environment and TERM=xterm-256color, or has that shell exec `command` as an interactive
    /// login shell, so an agent finds what ~/.zprofile and ~/.zshrc put on the PATH. SwiftTerm ignores a failed chdir and execs anyway,
    /// so `/bin/sh` changes directory first: a folder that has gone missing ends the process instead of opening it wherever the app was launched.
    func start(in folder: URL, generation: Int, command: [String] = []) {
        guard view.process.shellPid == 0 else { return }
        self.generation = generation
        // A view that has never been laid out — a session started from a tab that is not in front, or from the
        // recovered list — can be sized 0×0, and the shell is handed a 0-column terminal: zsh draws its prompt,
        // then its line editor fails with "error on TTY read: invalid argument" and exits 1 (2026-09-20). The
        // frame is what SwiftTerm measures, so it is given a real one before the process starts.
        if view.frame.width < 32 || view.frame.height < 32 {
            view.frame = NSRect(x: 0, y: 0, width: 640, height: 240)
        }
        let shell = LoginShell.path
        // The folder, the shell and each word of the command are arguments of their own, never text of the script.
        let script: [String]
        if command.isEmpty {
            script = [#"cd -- "$1" && exec "$2" -l"#, "sh", folder.path, shell]
        } else if let words = LoginShell.arguments(running: command) {
            script = [#"cd -- "$1" && shift && exec "$@""#, "sh", folder.path, shell] + words
        } else {
            // The Agents tab already says this shell can't run one; nothing launches.
            return exited(rawStatus: nil)
        }
        var environment = ProcessInfo.processInfo.environment
        environment["TERM"] = "xterm-256color"
        if let directory = watchEvents() { environment[AgentHooks.eventDirectoryVariable] = directory.path }
        // An app opened from Finder gets no locale; a locale that is set is never replaced.
        if ["LANG", "LC_ALL", "LC_CTYPE"].allSatisfy({ (environment[$0] ?? "").isEmpty }) {
            environment["LANG"] = Self.utf8Locale()
        }
        // A CLI that reports no turn end (gemini, opencode, antigravity) is working from here until it exits:
        // nothing else will ever say otherwise, and guessing it idle is what loses work.
        if let directory = eventDirectory, AgentProtocol.of(command.first).mustNotBeEndedWhileIdle, command.first != nil {
            AgentHooks.markWorking(.turnStarted, in: directory, protocol: AgentProtocol.of(command.first))
        }
        view.startProcess(executable: "/bin/sh",
                          args: ["-c"] + script,
                          environment: environment.map { "\($0.key)=\($0.value)" },
                          currentDirectory: folder.path)
        let pid = view.process.shellPid
        guard pid != 0 else { return exited(rawStatus: nil) }
        LiveShells.shared.insert(self)
        watchExit(of: pid)
        view.focusOnAttach = true
        view.takeFocusIfAsked()
    }

    /// The last non-empty lines on the terminal's screen and scrollback, oldest first — read from the buffer
    /// SwiftTerm already keeps, so nothing taps the byte stream or parses escapes a second time. Read at exit,
    /// while the view is still the transcript. `getTopVisibleRow()` is the scrollback above the screen when
    /// the view sits at the bottom, as an unwatched headless run's does; probing past it catches lines below
    /// a scrolled-up view, and the alternate screen (no scrollback) degrades to the visible rows.
    func transcriptTail(limit: Int = 40) -> [String] {
        let terminal = view.getTerminal()
        var total = terminal.getTopVisibleRow() + terminal.rows
        while terminal.getScrollInvariantLine(row: total) != nil { total += 1 }
        var lines: [String] = []
        var row = total - 1
        while row >= 0, lines.count < limit {
            if let line = terminal.getScrollInvariantLine(row: row) {
                let text = line.translateToString(trimRight: true).trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty { lines.insert(text, at: 0) }
            }
            row -= 1
        }
        return lines
    }

    /// SIGHUP now, then SIGKILL 2 s later to whatever of the shell and its foreground job is still there.
    func end() {
        guard isRunning else { return }
        wasEnded = true
        send(SIGHUP)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            send(SIGKILL)
            LiveShells.shared.remove(self)
        }
    }

    /// Signals the shell's own group and the terminal's foreground job group, as closing a Terminal window does.
    /// The shell is never signalled once its exit has been reaped, and a job group only while its leader is still in the shell's session,
    /// which keeps the shell's pid from being reused, so neither can reach another process.
    fileprivate func send(_ signal: Int32) {
        let pid = view.process.shellPid
        guard pid > 0 else { return }
        if !hasExited {
            let foreground = tcgetpgrp(view.process.childfd)
            if foreground > 0, foreground != pid { jobGroups.insert(foreground) }
        }
        for group in jobGroups where getsid(group) == pid { kill(-group, signal) }
        if !hasExited, kill(-pid, signal) != 0 { kill(pid, signal) }
    }

    /// SwiftTerm 1.11.2 cancels its own exit monitor when the terminal reads end of file, which usually comes first,
    /// so the shell is watched and reaped here too. The first reap catches a shell that exited before the monitor was armed.
    private func watchExit(of pid: pid_t) {
        let monitor = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: .main)
        monitor.setEventHandler { [weak self] in
            MainActor.assumeIsolated { _ = self?.reap() }
        }
        monitor.activate()
        exitMonitor = monitor
        reap()
    }

    /// True once the shell has gone. Whichever of this and SwiftTerm's own reap collects the exit reports it; the other finds nothing.
    @discardableResult
    fileprivate func reap() -> Bool {
        guard isRunning else { return true }
        var status: Int32 = 0
        let result = waitpid(view.process.shellPid, &status, WNOHANG)
        guard result != 0 else { return false }
        exited(rawStatus: result > 0 ? status : nil)
        return true
    }

    private func exited(rawStatus: Int32?) {
        guard !hasExited else { return }
        hasExited = true
        readEvents()
        eventWatch?.cancel()
        eventWatch = nil
        if let eventDirectory { try? FileManager.default.removeItem(at: eventDirectory) }
        exitMonitor?.cancel()
        exitMonitor = nil
        // A job that outlived its shell stays listed until end()'s SIGKILL, so quit can still reach it.
        if !hasLiveJobs { LiveShells.shared.remove(self) }
        onExit(self, Self.exitStatus(rawStatus))
    }

    /// A private folder for this session's hook events, watched for writes. nil when it cannot be made, which only
    /// costs the notifications.
    private func watchEvents() -> URL? {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("devdesk-events", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        guard (try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)) != nil else { return nil }
        let descriptor = open(directory.path, O_EVTONLY)
        guard descriptor >= 0 else { return nil }
        let watch = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: .write, queue: .main)
        watch.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.readEvents() } }
        watch.setCancelHandler { close(descriptor) }
        watch.activate()
        eventDirectory = directory
        eventWatch = watch
        return directory
    }

    /// Each finished event file once, oldest first; a dotfile is still being written and is left for the next pass.
    private func readEvents() {
        guard let eventDirectory,
              let names = try? FileManager.default.contentsOfDirectory(atPath: eventDirectory.path) else { return }
        for name in names.sorted() where !name.hasPrefix(".") {
            let file = eventDirectory.appendingPathComponent(name)
            let contents = (try? Data(contentsOf: file)) ?? Data()
            try? FileManager.default.removeItem(at: file)
            if let event = AgentHooks.event(fileName: name, contents: contents) {
                AgentHooks.markWorking(event, in: eventDirectory, protocol: AgentProtocol.of(executable))
                onEvent?(event)
            }
        }
    }

    /// waitpid's raw status. A shell killed by a signal reads as 128 + the signal, as `$?` shows it.
    private static func exitStatus(_ raw: Int32?) -> Int32? {
        guard let raw else { return nil }
        let signal = raw & 0x7f
        return signal == 0 ? (raw >> 8) & 0xff : 128 + signal
    }

    /// What Terminal sets for an app opened from Finder: the user's own locale when the system has it, else en_US.
    private static func utf8Locale() -> String {
        let name = Locale.current.identifier + ".UTF-8"
        return FileManager.default.fileExists(atPath: "/usr/share/locale/" + name) ? name : "en_US.UTF-8"
    }

    nonisolated func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
    nonisolated func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
    nonisolated func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

    /// When SwiftTerm's own exit monitor does fire, it has already reaped the shell with waitpid, and calls this on the main queue.
    nonisolated func processTerminated(source: TerminalView, exitCode: Int32?) {
        MainActor.assumeIsolated { exited(rawStatus: exitCode) }
    }
}

/// Takes keyboard focus the first time it lands in a window after a start, so the user can type straight away.
final class FocusingTerminalView: LocalProcessTerminalView {
    var focusOnAttach = false
    /// The app says what a bell means (a notification, with the chosen sound) instead of SwiftTerm's system beep.
    var onBell: (() -> Void)?

    override func bell(source: Terminal) { onBell?() }

    /// Every keystroke and every typed line reaches the process through here, so this is where Dev Desk learns
    /// that a turn has begun — without a hook, for any CLI. Return is the send; the rest is composing.
    override func send(source: Terminal, data: ArraySlice<UInt8>) {
        if data.contains(0x0d) { onSend?() }
        super.send(source: source, data: data)
    }

    /// Called when a line is sent to whatever runs in this terminal.
    var onSend: (() -> Void)?

    /// SwiftTerm 1.11.2 only ever scrolls its own scrollback, and a full-screen program (claude, codex, less) draws on the
    /// alternate screen, which has none — so the wheel did nothing there. The wheel goes to the program instead: as wheel
    /// events when it tracks the mouse, else as arrow keys, the alternate-scroll behaviour Terminal and iTerm have.
    /// True when the wheel went to the program; false leaves the event to SwiftTerm's own scrollback. `scrollWheel` is
    /// not open in SwiftTerm, so the host's event monitor calls this.
    func forwardScroll(_ event: NSEvent) -> Bool {
        let terminal = getTerminal()
        let reports = allowMouseReporting && terminal.mouseMode != .off
        guard event.deltaY != 0, reports || terminal.isCurrentBufferAlternate else { return false }
        let magnitude = abs(event.deltaY)
        let lines = magnitude > 5 ? 5 : magnitude > 1 ? 3 : 1
        let up = event.deltaY > 0
        if reports {
            let point = convert(event.locationInWindow, from: nil)
            let col = min(max(Int(point.x / max(bounds.width, 1) * CGFloat(terminal.cols)), 0), terminal.cols - 1)
            let row = min(max(Int((bounds.height - point.y) / max(bounds.height, 1) * CGFloat(terminal.rows)), 0), terminal.rows - 1)
            let flags = terminal.encodeButton(button: up ? 4 : 5, release: false, shift: event.modifierFlags.contains(.shift),
                                              meta: event.modifierFlags.contains(.option), control: event.modifierFlags.contains(.control))
            for _ in 0..<lines { terminal.sendEvent(buttonFlags: flags, x: col, y: row) }
        } else {
            let key = terminal.applicationCursor ? (up ? "\u{1b}OA" : "\u{1b}OB") : (up ? "\u{1b}[A" : "\u{1b}[B")
            send(txt: String(repeating: key, count: lines))
        }
        return true
    }

    /// What the arrows and delete report, whatever modifier is held: their characters are the private-use
    /// ones AppKit gives function keys, so the key itself is read from the code.
    private enum KeyCode {
        static let left: UInt16 = 123
        static let right: UInt16 = 124
        static let delete: UInt16 = 51
    }

    /// Word and line motion, which macOS puts on ⌥/⌘ with the arrows and delete, and which SwiftTerm sends
    /// nothing for: Option types characters here rather than acting as Meta (`optionAsMetaKey` stays false, as
    /// Terminal has it by default), so ⌥← used to insert a stray character and ⌘← to do nothing at all. Each
    /// combination is sent as the sequence readline and zsh already answer — typed into the shell, exactly as
    /// the user would. Anything else is the terminal's own business.
    ///
    /// It is answered here rather than in `keyDown`, which SwiftTerm declares public but not open and so cannot
    /// be overridden from this module: the window offers every key-down to its view hierarchy as a possible key
    /// equivalent first, which is early enough, and the guard keeps a terminal that is not being typed into from
    /// answering for one that is.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown, window?.firstResponder === self else {
            return super.performKeyEquivalent(with: event)
        }
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let option = modifiers.contains(.option)
        let command = modifiers.contains(.command)
        switch (event.keyCode, option, command) {
        case (KeyCode.left, true, false): send(txt: "\u{1b}b")    // ⌥← one word back
        case (KeyCode.right, true, false): send(txt: "\u{1b}f")   // ⌥→ one word on
        case (KeyCode.left, false, true): send(txt: "\u{01}")     // ⌘← Ctrl-A, the start of the line
        case (KeyCode.right, false, true): send(txt: "\u{05}")    // ⌘→ Ctrl-E, the end of the line
        case (KeyCode.delete, true, false): send(txt: "\u{17}")   // ⌥⌫ Ctrl-W, the word behind the caret
        case (KeyCode.delete, false, true): send(txt: "\u{15}")   // ⌘⌫ Ctrl-U, back to the start of the line
        default: return super.performKeyEquivalent(with: event)
        }
        return true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        takeFocusIfAsked()
    }

    func takeFocusIfAsked() {
        guard focusOnAttach, let window else { return }
        focusOnAttach = false
        window.makeFirstResponder(self)
    }
}

/// Ends the window's shells and agents when it closes (⌘W or the close button). Quit is handled once for every window by `LiveShells`.
struct ShellLifetimeHook: NSViewRepresentable {
    let registries: [ShellTerminalRegistry]

    func makeNSView(context: Context) -> ShellLifetimeView { ShellLifetimeView(registries: registries) }
    func updateNSView(_ nsView: ShellLifetimeView, context: Context) {}
}

final class ShellLifetimeView: NSView {
    private let registries: [ShellTerminalRegistry]

    init(registries: [ShellTerminalRegistry]) {
        self.registries = registries
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { return nil }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        let center = NotificationCenter.default
        if let window { center.removeObserver(self, name: NSWindow.willCloseNotification, object: window) }
        if let newWindow {
            center.addObserver(self, selector: #selector(windowWillClose), name: NSWindow.willCloseNotification, object: newWindow)
        }
    }

    @objc private func windowWillClose(_ notification: Notification) { registries.forEach { $0.endAll() } }
}

private struct TerminalsKey: EnvironmentKey {
    static let defaultValue: ShellTerminalRegistry? = nil
}

extension EnvironmentValues {
    /// The window's sessions — one per task, shell or agent (ADR 0026). Nil outside a project window, where
    /// nothing can start one.
    var terminals: ShellTerminalRegistry? {
        get { self[TerminalsKey.self] }
        set { self[TerminalsKey.self] = newValue }
    }
}

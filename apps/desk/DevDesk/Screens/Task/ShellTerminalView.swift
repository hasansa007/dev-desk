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

    func show(_ terminal: NSView) {
        guard terminal.superview !== self else { return }
        subviews.forEach { $0.removeFromSuperview() }
        terminal.frame = bounds
        terminal.autoresizingMask = [.width, .height]
        addSubview(terminal)
        // Re-parenting into a dialog leaves first responder wherever it was — on the sheet's buttons, which
        // then take ↑/↓ before the terminal sees them. A terminal that has just appeared is the thing being
        // looked at, so it asks for focus again.
        if let focusing = terminal as? FocusingTerminalView {
            focusing.focusOnAttach = true
            focusing.takeFocusIfAsked()
        }
    }

    /// The app's events reach a local monitor before any view, so this holds whatever SwiftUI draws around the terminal.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        clickMonitor = window == nil ? nil : LocalEventMonitor([.leftMouseDown, .rightMouseDown]) { [weak self] event in
            self?.focusTerminal(clickedBy: event)
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
        if let executable = command.first { executables[taskID] = executable }
        terminal(for: taskID).start(in: folder, generation: sessions.generation(for: taskID), command: command)
    }

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
                                 worktreeLocation: worktreeLocation, baseRef: task.baseRef, refusingRoot: refusingRoot)
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
        let prompt = AgentLaunch.prompt(skillRoot: AgentLaunch.skillRoot, taskNumber: task.taskNumber, hasBranch: !(task.branch ?? "").isEmpty, mode: mode)
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
        // The exit carries the generation its process started under, so a late exit can't end a session started after it.
        let terminal = ShellTerminal { [weak self] terminal, status in
            guard let self else { return }
            sessions.markEnded(taskID: taskID, status: status, generation: terminal.generation)
            if terminals[taskID] === terminal { terminals[taskID] = nil }
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
        // An app opened from Finder gets no locale; a locale that is set is never replaced.
        if ["LANG", "LC_ALL", "LC_CTYPE"].allSatisfy({ (environment[$0] ?? "").isEmpty }) {
            environment["LANG"] = Self.utf8Locale()
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

    /// SIGHUP now, then SIGKILL 2 s later to whatever of the shell and its foreground job is still there.
    func end() {
        guard isRunning else { return }
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
        exitMonitor?.cancel()
        exitMonitor = nil
        // A job that outlived its shell stays listed until end()'s SIGKILL, so quit can still reach it.
        if !hasLiveJobs { LiveShells.shared.remove(self) }
        onExit(self, Self.exitStatus(rawStatus))
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

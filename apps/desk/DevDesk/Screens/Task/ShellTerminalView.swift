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

/// Holds the registry's terminal as its only subview, taking it from whichever pane showed it last.
final class ShellTerminalHost: NSView {
    func show(_ terminal: NSView) {
        guard terminal.superview !== self else { return }
        subviews.forEach { $0.removeFromSuperview() }
        terminal.frame = bounds
        terminal.autoresizingMask = [.width, .height]
        addSubview(terminal)
    }
}

/// One window's shells, keyed by task id. Each outlives its pane, so switching tasks or hiding the dock keeps it running.
@MainActor
final class ShellTerminalRegistry {
    private let sessions: ShellSessions
    private var terminals: [String: ShellTerminal] = [:]
    /// Set when the window closes, so a start still preparing its folder then launches nothing.
    private var isClosed = false

    init(sessions: ShellSessions) {
        self.sessions = sessions
    }

    /// The same view on every call until its shell exits; the next start then gets a fresh one rather than the old screen.
    func view(for taskID: String) -> LocalProcessTerminalView {
        terminal(for: taskID).view
    }

    /// Called once the session is running, so the generation read here is the one this process belongs to.
    func start(taskID: String, folder: URL) {
        guard !isClosed else { return }
        terminal(for: taskID).start(in: folder, generation: sessions.generation(for: taskID))
    }

    func end(taskID: String) {
        terminals[taskID]?.end()
    }

    /// The window is closing: ends every shell, and refuses the starts that are still preparing their folder.
    func endAll() {
        isClosed = true
        terminals.values.forEach { $0.end() }
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

/// Every live shell in the app, across windows. Holding them here keeps a shell that is being ended alive until it is gone,
/// and lets quit end them all with one wait of at most 2 s rather than one per window.
@MainActor
final class LiveShells {
    static let shared = LiveShells()
    private var shells: [ObjectIdentifier: ShellTerminal] = [:]
    private var terminateObserver: NSObjectProtocol?

    private init() {
        terminateObserver = NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification,
                                                                   object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { LiveShells.shared.endAllBeforeQuit() }
        }
    }

    func insert(_ shell: ShellTerminal) { shells[ObjectIdentifier(shell)] = shell }
    func remove(_ shell: ShellTerminal) { shells[ObjectIdentifier(shell)] = nil }

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

    /// Runs `$SHELL -l` in `folder` with the user's environment and TERM=xterm-256color. SwiftTerm ignores a failed chdir and execs anyway,
    /// so `/bin/sh` changes directory first: a folder that has gone missing ends the shell instead of opening it wherever the app was launched.
    func start(in folder: URL, generation: Int) {
        guard view.process.shellPid == 0 else { return }
        self.generation = generation
        var environment = ProcessInfo.processInfo.environment
        let shell = environment["SHELL"].flatMap { $0.isEmpty ? nil : $0 } ?? "/bin/zsh"
        environment["TERM"] = "xterm-256color"
        // An app opened from Finder gets no locale; a locale that is set is never replaced.
        if ["LANG", "LC_ALL", "LC_CTYPE"].allSatisfy({ (environment[$0] ?? "").isEmpty }) {
            environment["LANG"] = Self.utf8Locale()
        }
        view.startProcess(executable: "/bin/sh",
                          args: ["-c", #"cd -- "$1" && exec "$2" -l"#, "sh", folder.path, shell],
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

/// Ends the window's shells when it closes (⌘W or the close button). Quit is handled once for every window by `LiveShells`.
struct ShellLifetimeHook: NSViewRepresentable {
    let terminals: ShellTerminalRegistry

    func makeNSView(context: Context) -> ShellLifetimeView { ShellLifetimeView(terminals: terminals) }
    func updateNSView(_ nsView: ShellLifetimeView, context: Context) {}
}

final class ShellLifetimeView: NSView {
    private let terminals: ShellTerminalRegistry

    init(terminals: ShellTerminalRegistry) {
        self.terminals = terminals
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

    @objc private func windowWillClose(_ notification: Notification) { terminals.endAll() }
}

private struct ShellTerminalsKey: EnvironmentKey {
    static let defaultValue: ShellTerminalRegistry? = nil
}

extension EnvironmentValues {
    /// The window's shells; nil outside a project window, where the Shell tab can't start one.
    var shellTerminals: ShellTerminalRegistry? {
        get { self[ShellTerminalsKey.self] }
        set { self[ShellTerminalsKey.self] = newValue }
    }
}

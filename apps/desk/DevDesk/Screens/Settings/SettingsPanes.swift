import AppKit
import DeskCore
import SwiftUI
import UserNotifications

// Every pane here is cards of `SettingRow`s from `SettingsControls.swift`. The rule the rewrite enforces:
// one row, one control, one line saying what changing it does — and where there is nothing to change, the
// reason, in the row, rather than a control that quietly does nothing (2026-09-20).

@MainActor
private func isGitHubUnavailable(_ model: ProjectWindowModel) -> Bool {
    model.snapshot?.connections.first { $0.id == "github" }?.state == .unavailable
}

/// A sample project has no folder on disk, which is why half the project-scoped settings have nothing to
/// write to. One sentence, said the same way everywhere it is true.
@MainActor
private func noFolderReason(_ model: ProjectWindowModel) -> String? {
    model.projectRoot == nil ? "A sample project has no folder on disk, so there is nothing here to save to." : nil
}

/// The failed "GitHub is unavailable" callout and its Reconnect popover, shared by two panes.
private struct GitHubUnavailableNotice: View {
    @State private var showHelp = false

    var body: some View {
        NoticeBanner(tone: .failed, title: "GitHub is unavailable",
                     message: "Issue search, issue links, and proposed tracker updates are disabled. Local repository facts are still available.",
                     style: .callout) {
            Button("Reconnect…") { showHelp = true }
                .buttonStyle(DeskButtonStyle(kind: .secondary, size: .smallWide))
                .popover(isPresented: $showHelp) {
                    MarkdownText("Run `gh auth login` in Terminal, or add a GitHub remote to this repository, then reload this window (⌘R).")
                        .padding(12)
                        .frame(width: 280)
                }
        }
    }
}

// MARK: - General

struct GeneralPane: View {
    /// nil on Home, where no project is selected: the Dev Desk card is app-wide and stands on its own, and
    /// the Diagnostics card simply is not there — dev doctor runs at a project root or not at all.
    let model: ProjectWindowModel?
    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PaneHeader("General", scope: .everyProject,
                       summary: "This app itself: which build is running, and the CLI's own check of the machine.")

            SettingCard("Dev Desk") {
                SettingRow("Version", why: "The build installed in ~/Applications. `apps/desk/install.sh` replaces it.") {
                    Text(version)
                        .font(DeskFont.mono(12))
                        .foregroundStyle(DeskColor.secondaryInk)
                        .textSelection(.enabled)
                }
            }

            if let model {
                SettingCard("Diagnostics") {
                    SettingRow("dev doctor",
                               why: "Opens a terminal at the project root and runs the CLI's own check of this machine and this repository. Settings closes, because the terminal comes to the front.",
                               unavailable: model.canRunDoors ? nil : "A sample project has no folder, so there is nothing to check.") {
                        Button("Run dev doctor") {
                            model.dismissSheet()
                            model.runDoctor()
                        }
                        .buttonStyle(DeskButtonStyle(kind: .secondary, size: .small))
                    }
                }
            }
        }
    }
}

// MARK: - Appearance

struct AppearancePane: View {
    @AppStorage(PreferenceKey.appearance) private var appearance = AppearanceChoice.system
    @AppStorage(PreferenceKey.appIcon) private var appIcon = AppIconChoice.system
    @AppStorage(PreferenceKey.terminalFontSize) private var terminalFontSize = 12.0

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PaneHeader("Appearance", scope: .everyProject,
                       summary: "How Dev Desk is drawn on this Mac. Nothing here touches a project or a run.")

            SettingCard("The window") {
                SettingRow("Appearance",
                           why: "Applied app-wide, not per window: alerts, open panels and the Open Project window follow it too. **System** tracks macOS.") {
                    Picker("", selection: $appearance) {
                        ForEach(AppearanceChoice.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .settingPicker(width: 210)
                    .accessibilityLabel("Appearance")
                }
                SettingBlockRow("App icon",
                                why: "Which artwork the Dock and ⌘-Tab show. **System** follows the appearance above, so it changes when that does.") {
                    HStack(spacing: 14) {
                        Picker("", selection: $appIcon) {
                            ForEach(AppIconChoice.allCases, id: \.self) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .settingPicker(width: 210)
                        .accessibilityLabel("App icon")
                        // The artwork the choice resolves to, so both icons are visible while choosing.
                        // Keyed on both preferences so a System choice repaints when Appearance changes.
                        if let preview = AppIconStyle.resolvedImage() {
                            Image(nsImage: preview)
                                .resizable()
                                .interpolation(.high)
                                .frame(width: 44, height: 44)
                                .id("\(appIcon.rawValue)-\(appearance.rawValue)")
                                .accessibilityHidden(true)
                        }
                    }
                }
                SettingRow("Terminal text size",
                           why: "The type inside every session tile. A terminal keeps its dark ground under Light, so only the size moves here.") {
                    Picker("", selection: $terminalFontSize) {
                        ForEach(Array(stride(from: 11.0, through: 14.0, by: 1.0)), id: \.self) { size in
                            Text("\(Int(size)) pt").tag(size)
                        }
                    }
                    .settingPicker(width: 110)
                    .accessibilityLabel("Terminal text size")
                }
            }
        }
        // Both preferences feed the resolution, so either changing re-applies the icon. System's
        // OS-driven case is re-applied by the effectiveAppearance observer in QuitGuard.
        .onChange(of: appIcon) { AppIconStyle.apply() }
        .onChange(of: appearance) { AppIconStyle.apply() }
    }
}

// MARK: - Agents and defaults

struct AgentsAndDefaultsPane: View {
    /// nil on Home. The three defaults are preferences and need no project; what is installed and what each
    /// CLI can do is read off a project's snapshot, so on Home those are absent rather than guessed at —
    /// resolving availability against no connections would report every agent as missing.
    let model: ProjectWindowModel?
    @AppStorage(PreferenceKey.defaultConnection) private var defaultConnection = AgentDefaults.connection
    @AppStorage(PreferenceKey.runMode) private var runMode = AgentDefaults.runMode
    @AppStorage(PreferenceKey.backgroundConnection) private var storedBackground = ""
    @AppStorage(PreferenceKey.sessionAgents) private var sessionAgents = SessionAgents.defaultBuiltIns
    @AppStorage(PreferenceKey.customSessionAgents) private var customSessionAgents = Data()
    @State private var newAgentName = ""
    @State private var newAgentCommand = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PaneHeader("Agents and defaults", scope: .everyProject,
                       summary: "What a Start begins: which CLI it runs, which one answers a background run, and how much it is allowed to do before it asks.")

            SettingCard("Defaults") {
                SettingRow("Connection",
                           why: "The agent a task, a door or a shell starts with unless the start sheet says otherwise. A change applies to the next start, never to one already running.",
                           unavailable: defaultConnectionProblem) {
                    Picker("", selection: $defaultConnection) {
                        ForEach(providers, id: \.self) { Text(label(for: $0)).tag($0) }
                    }
                    .settingPicker(width: 200)
                    .accessibilityLabel("Default connection")
                }
                SettingRow("Background runs",
                           why: "Tasks and doors run in a terminal with the connection above, any of the five. A background run — Findings or Ideation in the background, filing an issue, a diagram — needs a headless form this app can read, which only Claude and Codex have.") {
                    Picker("", selection: backgroundBinding) {
                        ForEach(BackgroundConnection.choices, id: \.self) { Text(label(for: $0)).tag($0) }
                    }
                    .settingPicker(width: 200)
                    .accessibilityLabel("Background runs")
                }
                SettingRow("Mode", why: modeDetail) {
                    Picker("", selection: $runMode) {
                        ForEach(RunMode.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .settingPicker(width: 200)
                    .accessibilityLabel("Default mode")
                }
            }

            sessionAgentsCard

            // Was titled "Capabilities of the selected connection" over a table of every connection, which
            // is a heading that describes a different table than the one under it (2026-09-20).
            if let model {
                SettingCard("What each connection can do", footer: capabilitiesNote) {
                    SettingRowShell { capabilitiesTable(model) }
                }
                if isGitHubUnavailable(model) { GitHubUnavailableNotice() }
            }
        }
    }

    // MARK: - Session agents

    /// What Sessions' *Start with* and its "+" list: a switch per built-in agent, then the developer's own, each a
    /// line typed into a login shell at the project root. A plain terminal is always listed and so is not here.
    private var sessionAgentsCard: some View {
        let custom = SessionAgents.decodeCustom(customSessionAgents)
        return SettingCard("Session agents",
                           footer: "What Sessions offers under Start with and behind the + after its tabs. A plain terminal is always listed.") {
            ForEach(AgentLaunch.runnableKinds, id: \.self) { agent in
                SettingToggle(title: AgentLaunch.displayName(agent), why: sessionAgentNote(agent),
                              isOn: builtInBinding(agent))
            }
            ForEach(custom) { agent in
                SettingRowShell {
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(agent.name)
                                .font(DeskFont.body)
                                .foregroundStyle(DeskColor.ink)
                            Text(agent.command)
                                .font(DeskFont.mono(11))
                                .foregroundStyle(DeskColor.mutedInk)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .help(agent.command)
                        }
                        Spacer(minLength: 8)
                        Button("Remove") {
                            customSessionAgents = SessionAgents.encodeCustom(custom.filter { $0.id != agent.id })
                        }
                        .buttonStyle(DeskButtonStyle(kind: .secondary, size: .mini))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            SettingBlockRow("Add an agent",
                            why: "Any CLI: its line is typed into a login shell at the project root, as you would type it.",
                            unavailable: nil) {
                HStack(spacing: 8) {
                    TextField("Name", text: $newAgentName).settingField(width: 130)
                    TextField("aider --model sonnet", text: $newAgentCommand).settingField(width: 300)
                    Button("Add", action: addSessionAgent)
                        .buttonStyle(DeskButtonStyle(kind: .secondary, size: .small))
                        .disabled(newAgentName.trimmed.isEmpty || newAgentCommand.trimmed.isEmpty)
                }
            }
        }
    }

    private func builtInBinding(_ agent: AgentKind) -> Binding<Bool> {
        Binding(get: { SessionAgents.builtIns(sessionAgents).contains(agent) },
                set: { isOn in
                    var listed = SessionAgents.builtIns(sessionAgents).filter { $0 != agent }
                    if isOn { listed.append(agent) }
                    sessionAgents = SessionAgents.store(listed)
                })
    }

    /// Listed or not, an agent says whether it could start: ticking one that is not installed is allowed — it shows
    /// in Sessions, dimmed, with the reason — but it should not be a surprise there.
    private func sessionAgentNote(_ agent: AgentKind) -> String {
        switch availability(AgentLaunch.connectionName(agent)) {
        case .some(.unavailable(let reason)): return "Runs in a terminal — \(StartRunners.shortReason(reason)) here."
        case .some(.ready), .none: return "Runs in a terminal at the project root."
        }
    }

    private func addSessionAgent() {
        let agent = CustomSessionAgent(name: newAgentName.trimmed, command: newAgentCommand.trimmed)
        customSessionAgents = SessionAgents.encodeCustom(SessionAgents.decodeCustom(customSessionAgents) + [agent])
        newAgentName = ""
        newAgentCommand = ""
    }

    /// Every project shares the app default, so with no project open the resolved mode is the same sentence.
    private var modeDetail: String {
        RunModeChoice.resolve(override: "", appDefault: runMode).detail
    }

    private var backgroundBinding: Binding<String> {
        Binding(get: { BackgroundConnection.resolve(stored: storedBackground, defaultConnection: defaultConnection) },
                set: { storedBackground = $0 })
    }

    /// Every agent a task can start with, installed or not — the list has to hold the one already chosen even
    /// when it has since been uninstalled, or the picker would silently show a different agent than is stored.
    private var providers: [String] { AgentLaunch.runnableKinds.map(AgentLaunch.connectionName) }

    /// A connection that is not installed says so in the picker itself. It used to say so only in the start
    /// sheet, which is one Start too late to find out.
    private func label(for name: String) -> String {
        switch availability(name) {
        case .some(.ready), .none: return name
        case .some(.unavailable): return "\(name) — unavailable"
        }
    }

    /// nil when there is no project to read the machine's connections from. Not "unavailable": an unknown
    /// state annotated as a missing install is the exact lie this annotation exists to stop.
    private func availability(_ name: String) -> AgentAvailability? {
        guard let snapshot = model?.snapshot else { return nil }
        return AgentAvailability.resolve(connectionName: name,
                                         connections: snapshot.connections,
                                         hasStandIn: DebugLaunch.agentExecutable != nil,
                                         terminalAgents: snapshot.terminalAgents)
    }

    /// The reason the *chosen* connection cannot run, in the chosen connection's row — the CLI's own words
    /// where it has them, since it knows better than this pane whether it is logged out or rate-limited.
    private var defaultConnectionProblem: String? {
        if case .some(.unavailable(let reason)) = availability(defaultConnection) { return reason }
        return nil
    }

    private var capabilitiesNote: String {
        [model?.snapshot?.capabilities.note,
         "Models are listed by the connected tool at runtime; Dev Desk stores no version names or pricing."]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// Scrolls sideways rather than squeezing: five columns do not fit a dialog's pane, and a truncated
    /// capability is worse than one you have to reach for.
    private func capabilitiesTable(_ model: ProjectWindowModel) -> some View {
        let matrix = model.snapshot?.capabilities
        return ScrollView(.horizontal, showsIndicators: true) {
            VStack(spacing: 6) {
                HStack(spacing: 0) {
                    Text("Capability").frame(width: 170, alignment: .leading)
                    ForEach(matrix?.providers ?? [], id: \.self) { provider in
                        Text(provider)
                            .fontWeight(provider == defaultConnection ? .semibold : .regular)
                            .foregroundStyle(provider == defaultConnection ? DeskColor.ink : DeskColor.mutedInk)
                            .frame(width: 92, alignment: .leading)
                    }
                }
                .font(DeskFont.mono(11.5))
                .foregroundStyle(DeskColor.mutedInk)

                ForEach(matrix?.rows ?? [], id: \.id) { row in
                    Rectangle().fill(DeskColor.rowDivider).frame(height: 1)
                    HStack(spacing: 0) {
                        Text(row.name)
                            .foregroundStyle(DeskColor.secondaryInk)
                            .frame(width: 170, alignment: .leading)
                        ForEach(Array(row.values.enumerated()), id: \.offset) { _, value in
                            Text(value.rawValue)
                                .foregroundStyle(color(for: value))
                                .frame(width: 92, alignment: .leading)
                        }
                    }
                    .font(DeskFont.mono(11.5))
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func color(for value: CapabilityValue) -> Color {
        switch value {
        case .yes: return DeskColor.tone(.running).foreground
        case .sometimes: return DeskColor.tone(.waiting).foreground
        case .no: return DeskColor.tone(.failed).foreground
        case .unknown, .notValidated: return DeskColor.faintInk
        }
    }
}

// MARK: - Accounts and connections

struct AccountsPane: View {
    let model: ProjectWindowModel
    @State private var signingOut: Connection?
    /// Set when Automation was refused and the command went to the clipboard instead, so the pane says so
    /// rather than appearing to do nothing.
    @State private var copied: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PaneHeader("Accounts and connections", scope: .everyProject,
                       summary: "Dev Desk never holds a credential: each CLI owns its own keychain, so signing in is that tool's own command, typed into a terminal you watch.")

            SettingCard("Connections", footer: model.snapshot?.connectionsNote ?? "") {
                ForEach(model.snapshot?.connections ?? []) { connection in
                    SettingRowShell { row(connection) }
                }
            }

            // Automation was refused, so the command went to the clipboard. Said here rather than nowhere,
            // which is what a refused sign-in looked like: a button that did nothing.
            if let copied {
                NoticeBanner(tone: .info, title: "The command is on your clipboard",
                             message: "Couldn't open your terminal, so `\(copied)` was copied instead — paste it into a terminal to finish.",
                             style: .callout)
            }

            if let account = model.snapshot?.projectFacts.first(where: { $0.key == "GitHub account" }) {
                KeyValueTable(rows: [account], keyWidth: 170)
            }

            if isGitHubUnavailable(model) { GitHubUnavailableNotice() }
        }
        .confirmationDialog("Sign out of \(signingOut?.name ?? "")?",
                            isPresented: Binding(get: { signingOut != nil }, set: { if !$0 { signingOut = nil } }),
                            titleVisibility: .visible) {
            Button("Sign out", role: .destructive) { if let signingOut { run(signingOut.auth?.signOut, for: signingOut) } }
            Button("Cancel", role: .cancel) { signingOut = nil }
        } message: {
            Text("Anything running on this connection stops working. The command runs in a terminal you can watch.")
        }
    }

    /// One connection: what it is, who it is, and the one action it has. A row with no action says why it has
    /// none rather than showing a dead button — a CLI that is not installed has nothing to sign into.
    private func row(_ connection: Connection) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                StatusDot(tone: tone(for: connection.state))
                Text(connection.name)
                    .font(DeskFont.body)
                    .foregroundStyle(DeskColor.ink)
                Spacer(minLength: 8)
                Text(connection.label)
                    .font(DeskFont.secondary)
                    .foregroundStyle(connection.isSignedOut ? DeskColor.tone(.failed).foreground : DeskColor.mutedInk)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(connection.detail ?? connection.label)
                action(connection)
            }
            if let detail = connection.detail, detail != connection.label {
                MarkdownText(detail, font: DeskFont.secondary, color: DeskColor.mutedInk)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder private func action(_ connection: Connection) -> some View {
        if let auth = connection.auth {
            // An interactive sign-in never shows Sign out: Gemini's is `/auth logout` inside its own
            // session, so there is no command here to run and a button would have to invent one.
            if connection.isSignedOut || auth.isInteractive {
                Button(auth.isInteractive ? "Open…" : "Sign in…") { run(auth.signIn, for: connection) }
                    .buttonStyle(DeskButtonStyle(kind: .secondary, size: .mini))
                    .help(auth.isInteractive
                          ? "Opens \(auth.signIn) in your terminal, where you can sign in from its own menu"
                          : "Runs \(auth.signIn) in your terminal")
            } else if let signOut = auth.signOut {
                Button("Sign out…") { signingOut = connection }
                    .buttonStyle(DeskButtonStyle(kind: .secondary, size: .mini))
                    .help("Runs \(signOut) in your terminal")
            }
        } else {
            // nil auth means there is nothing to sign into here. Saying so beats an empty column that reads
            // as a button that failed to draw.
            Text("no sign-in")
                .font(DeskFont.mono(10.5))
                .foregroundStyle(DeskColor.faintInk)
                .help("This tool has no sign-in command Dev Desk can run.")
        }
    }

    private func run(_ command: String?, for connection: Connection) {
        guard let command else { return }
        signingOut = nil
        switch model.runAuthCommand(command, connection: connection.name) {
        case .opened:
            // The terminal is in front now; the sheet would be behind it either way.
            model.dismissSheet()
        case .copied:
            copied = command
        }
    }

    private func tone(for state: ConnectionState) -> StatusTone {
        switch state {
        case .connected: return .running
        case .detected: return .info
        case .notConnected, .missing: return .neutral
        case .unavailable: return .failed
        }
    }
}

// MARK: - Notifications

struct NotificationsPane: View {
    @AppStorage(PreferenceKey.notifyDecisions) private var notifyDecisions = true
    @AppStorage(PreferenceKey.notifyCompletion) private var notifyCompletion = true
    @AppStorage(PreferenceKey.notifyFailures) private var notifyFailures = true
    @AppStorage(PreferenceKey.notifySound) private var sound = NotificationSound.defaultName
    @State private var permission: UNAuthorizationStatus?

    /// macOS asks once; a denial is never asked again. Every toggle below is inert until this is allowed, so
    /// the denial is repeated onto each of them rather than stated once at the top and forgotten.
    private var permissionProblem: String? {
        switch permission {
        case .denied: return "Notifications are off for Dev Desk in System Settings, so nothing below can show a banner. The sound still plays."
        case .notDetermined: return "macOS hasn't been asked yet, so no banner appears until you allow it above."
        default: return nil
        }
    }

    private var permissionLabel: String {
        switch permission {
        case .authorized, .provisional, .ephemeral: return "Allowed"
        case .denied: return "Off in System Settings"
        case .notDetermined: return "Not asked yet"
        default: return "Checking…"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PaneHeader("Notifications", scope: .everyProject,
                       summary: "When Dev Desk is allowed to interrupt you. Background runs and terminal sessions both notify.")

            SettingCard("Permission") {
                SettingRow("macOS", why: "Granted once, to the app. Dev Desk cannot ask again after a refusal — System Settings is the only way back.") {
                    HStack(spacing: 8) {
                        Text(permissionLabel)
                            .font(DeskFont.secondary)
                            .foregroundStyle(DeskColor.secondaryInk)
                        if permission == .notDetermined {
                            Button("Allow…") { ask() }
                                .buttonStyle(DeskButtonStyle(kind: .secondary, size: .small))
                        } else if permission == .denied {
                            Button("Open System Settings") { openSystemSettings() }
                                .buttonStyle(DeskButtonStyle(kind: .secondary, size: .small))
                        }
                    }
                }
            }

            SettingCard("Tell me about",
                        footer: "Claude and Codex report exactly when they need you or finish a turn; other tools are heard through the terminal bell, which only guesses.") {
                SettingToggle(title: "Decisions that need you",
                              why: "A run has stopped and is waiting on an answer. The one worth leaving on — nothing moves until you reply.",
                              unavailable: permissionProblem, isOn: $notifyDecisions)
                SettingToggle(title: "Completed work",
                              why: "A task or a door finished on its own.",
                              unavailable: permissionProblem, isOn: $notifyCompletion)
                SettingToggle(title: "Failed runs",
                              why: "A run ended with an error, in a session or in the background.",
                              unavailable: permissionProblem, isOn: $notifyFailures)
            }

            SettingCard("Sound") {
                SettingRow("Sound",
                           why: "Played by the app, so it sounds even when the banner is skipped — including when the session is already on screen. **None** leaves the banner silent.") {
                    HStack(spacing: 8) {
                        Picker("", selection: $sound) {
                            Text("None").tag("")
                            ForEach(NotificationSound.choices, id: \.self) { Text($0).tag($0) }
                        }
                        .settingPicker(width: 150)
                        .accessibilityLabel("Notification sound")
                        Button("Preview") { NotificationSound.play(sound) }
                            .buttonStyle(DeskButtonStyle(kind: .secondary, size: .small))
                            .disabled(sound.isEmpty)
                    }
                }
            }
        }
        .task { await readPermission() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await readPermission() }
        }
    }

    private func ask() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in
            Task { @MainActor in await readPermission() }
        }
    }

    private func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(Bundle.main.bundleIdentifier ?? "")") else { return }
        NSWorkspace.shared.open(url)
    }

    @MainActor private func readPermission() async {
        permission = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }
}

// MARK: - Execution

struct ExecutionPane: View {
    @AppStorage(PreferenceKey.worktreeLocation) private var worktreeLocation = AgentDefaults.worktreeLocation
    @AppStorage(PreferenceKey.agentLimit) private var agentLimit = AgentLimit.defaultValue
    @AppStorage(PreferenceKey.confirmQuit) private var confirmQuit = true
    @AppStorage(PreferenceKey.autoReload) private var autoReload = false
    @AppStorage(PreferenceKey.runMaxAgents) private var runMaxAgents = RunStops.defaultMaxAgents

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PaneHeader("Execution", scope: .everyProject,
                       summary: "Where parallel work is checked out, how much of it may run at once, and when this app talks to git and to you.")

            SettingCard("Task checkouts") {
                SettingBlockRow("Worktree location",
                                why: "Task worktrees are created here when you start a shell or an agent for a task that isn't checked out yet, including a detached one for a task with no branch.",
                                unavailable: pathProblem) {
                    HStack(spacing: 8) {
                        // A typo used to surface much later, as a git error when a session tried to start in it.
                        TextField("", text: $worktreeLocation)
                            .settingField(width: 280, isInvalid: pathProblem != nil)
                            .accessibilityLabel("Worktree location")
                        Button("Choose…") { chooseFolder() }
                            .buttonStyle(DeskButtonStyle(kind: .secondary, size: .small))
                    }
                }
            }

            SettingCard("How much runs at once") {
                SettingStepper(title: "Agents at once",
                               why: "Across every project and every window. A start beyond the limit queues instead of failing.",
                               valueLabel: agentLimit == 1 ? "1 agent" : "\(agentLimit) agents",
                               range: AgentLimit.range, value: $agentLimit)
                SettingStepper(title: "Agents in one findings or ideation run",
                               why: "Finders and checkers together (ADR 0043). A run whose plan needs more starts nothing and says why.",
                               valueLabel: "\(runMaxAgents) agents",
                               range: RunStops.maxAgentsRange, step: 5, value: $runMaxAgents)
            }

            SettingCard("This app") {
                SettingToggle(title: "Reload every 2 minutes",
                              why: "Off, the board is read again when you act — opening, ⌘R, a start, a stop, a move — and each of those first pulls from origin. The timed reload never pulls.",
                              isOn: $autoReload)
                SettingToggle(title: "Ask before quitting while something is running",
                              why: "Quitting ends every session and background run. The question is only ever asked when one of them is live.",
                              isOn: $confirmQuit)
            }
        }
    }

    /// Why this location cannot hold worktrees, or nil when it can. Checked as it is typed, because the
    /// alternative is finding out from a git error at the moment a task was supposed to start.
    private var pathProblem: String? {
        let trimmed = worktreeLocation.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return "A folder is needed: worktrees have to be created somewhere." }
        let expanded = (trimmed as NSString).expandingTildeInPath
        guard expanded.hasPrefix("/") else { return "Use a full path, or one starting with ~." }
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: expanded, isDirectory: &isDirectory) {
            if !isDirectory.boolValue { return "That path is a file, not a folder." }
            if !FileManager.default.isWritableFile(atPath: expanded) { return "That folder cannot be written to." }
            return nil
        }
        // Not there yet is fine — it is created on first use — as long as something above it exists.
        let parent = (expanded as NSString).deletingLastPathComponent
        return FileManager.default.fileExists(atPath: parent) ? nil : "Neither that folder nor the one above it exists."
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        worktreeLocation = url.path.hasPrefix(home) ? "~" + url.path.dropFirst(home.count) : url.path
    }
}

// MARK: - Project overrides

struct ProjectOverridesPane: View {
    let model: ProjectWindowModel

    /// What a reset would actually find here, so the button is not a mystery until it is pressed.
    private var resetSummary: String {
        let ignored = model.ignoredFindingsCount
        let reports = model.findingsReports.count
        if ignored == 0 && reports == 0 { return "Nothing to clear: no reports, no set-aside findings." }
        let parts = [reports > 0 ? "\(reports) report\(reports == 1 ? "" : "s")" : nil,
                     ignored > 0 ? "\(ignored) finding\(ignored == 1 ? "" : "s") set aside" : nil].compactMap { $0 }
        return parts.joined(separator: " · ") + "."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PaneHeader("Project overrides", scope: .thisProject,
                       summary: "Two different things, kept apart: facts this repository owns, and the preferences Dev Desk keeps about it on this Mac.")

            // The caption used to speak for the repository facts and deny the two Dev Desk preferences that
            // were sitting right below it under the same heading.
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel("From the repository")
                // `KeyValueTable` is already a card of rows, so it stands where a `SettingCard` would.
                if (model.snapshot?.projectFacts ?? []).isEmpty {
                    UnavailableLine("Nothing read yet — a sample project has no repository to read from.")
                } else {
                    KeyValueTable(rows: model.snapshot?.projectFacts ?? [], keyWidth: 170)
                }
                SettingNote("Read from the repository. Dev Desk never overrides the repository's own configuration.")
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // These were hidden outright for a sample, which reads as "this project has no Auto" rather than
            // "a sample has nowhere to keep one" (2026-09-20).
            SettingCard("Dev Desk, for this project", footer: "Kept on this Mac, not in the repository.") {
                AutoModeSetting(ref: model.ref, unavailable: noFolderReason(model))
                SettingRow("Reset findings",
                           why: resetSummary + " Clears this project's findings reports and the findings you set aside, so the next run starts from nothing.",
                           unavailable: noFolderReason(model)) {
                    Button("Reset findings…") {
                        model.dismissSheet()
                        model.present(.resetFindings)
                    }
                    .buttonStyle(DeskButtonStyle(kind: .secondary, size: .small))
                }
            }
        }
    }
}

/// This project's Auto. Turning it on asks first, since it spends tokens unattended; Cancel leaves it off.
private struct AutoModeSetting: View {
    @AppStorage private var autoMode: Bool
    @AppStorage(PreferenceKey.agentLimit) private var agentLimit = AgentLimit.defaultValue
    @State private var confirming = false
    private let unavailable: String?

    init(ref: ProjectRef, unavailable: String?) {
        _autoMode = AppStorage(wrappedValue: false, PreferenceKey.autoMode(ref))
        self.unavailable = unavailable
    }

    var body: some View {
        let notice = AutoAgents.notice(limit: min(max(agentLimit, AgentLimit.range.lowerBound), AgentLimit.range.upperBound))
        SettingRow("Auto", why: notice, unavailable: unavailable) {
            Toggle("", isOn: Binding(get: { autoMode }, set: { isOn in
                if isOn { confirming = true } else { autoMode = false }
            }))
            .toggleStyle(.switch)
            .labelsHidden()
            .accessibilityLabel("Auto")
        }
        .alert(Text(verbatim: notice), isPresented: $confirming) {
            Button("Turn on Auto") { autoMode = true }
            Button("Cancel", role: .cancel) {}
        }
    }
}

// MARK: - Work

/// Settings › Work (ADR 0046): this project's choices for the Work tab, kept in `.devdesk/work.json` beside the work.
struct WorkSettingsPane: View {
    let model: ProjectWindowModel
    @State private var settings = WorkSettings()
    @State private var loaded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PaneHeader("Work", scope: .thisProject,
                       summary: "How the Work tab decides what is next and what is finished. Kept in `.devdesk/work.json` beside the work, so `dev:board` reads the same choices.")

            SettingCard("Next up") {
                SettingRow("Working now follows",
                           why: settings.nextUpFollows == .plan
                                ? "The milestone at the top of Work's list is Working now; **Move to top** changes it. With no order set yet, the nearest due date decides."
                                : "The open milestone due soonest is Working now, whatever order the list is in.",
                           unavailable: unavailable) {
                    Picker("", selection: binding(\.nextUpFollows)) {
                        Text("Plan order").tag(WorkSettings.NextUpSource.plan)
                        Text("Due date").tag(WorkSettings.NextUpSource.dueDate)
                    }
                    .pickerStyle(.segmented)
                    .settingPicker(width: 210)
                    .accessibilityLabel("Working now follows")
                }
            }

            SettingCard("Done and Review") {
                SettingStepper(title: "Done shows",
                               why: "Merged work past this count is summarised as “N more” at the foot of Done. 0 shows all of it.",
                               valueLabel: settings.doneLimit == 0 ? "everything" : "latest \(settings.doneLimit)",
                               range: 0...100, step: 5, unavailable: unavailable, value: binding(\.doneLimit))
                SettingToggle(title: "Pull requests without an issue",
                              why: "A pull request with no issue behind it — a findings report, a docs edit — is not a task. Off keeps Review to tasks only.",
                              unavailable: unavailable, isOn: binding(\.showsPullRequestsWithoutIssue))
            }
        }
        .onAppear {
            guard !loaded else { return }
            settings = model.snapshot?.workSettings ?? WorkSettings()
            loaded = true
        }
    }

    /// A sample has no `.devdesk` to write to, so every control here would change a value that is discarded
    /// the moment the window reloads.
    private var unavailable: String? { noFolderReason(model) }

    private func binding<T>(_ key: WritableKeyPath<WorkSettings, T>) -> Binding<T> {
        Binding(get: { settings[keyPath: key] }, set: { value in
            settings[keyPath: key] = value
            let saved = settings
            Task { await model.setWorkSettings(saved) }
        })
    }
}

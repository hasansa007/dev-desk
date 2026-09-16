import AppKit
import DeskCore
import SwiftUI

/// A form row with a 200-wide right-aligned label, matching D:715's field rows.
private struct SettingsRow<Content: View>: View {
    let label: String
    let content: Content

    init(_ label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Text(label)
                .foregroundStyle(DeskColor.secondaryInk)
                .frame(width: 200, alignment: .trailing)
            content
        }
    }
}

/// Whose setting this is. A pane that does not say it invites the question on every visit — and the
/// Project overrides pane answered it wrongly, with a caption denying the two Dev Desk preferences under it.
enum SettingScope {
    case everyProject, thisProject

    var label: String {
        switch self {
        case .everyProject: return "all projects"
        case .thisProject: return "this project"
        }
    }
}

/// A pane's heading and the scope of everything under it.
struct PaneTitle: View {
    let title: String
    let scope: SettingScope

    init(_ title: String, scope: SettingScope) {
        self.title = title
        self.scope = scope
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(title).font(DeskFont.section)
            PropertyChip(scope.label)
            Spacer(minLength: 0)
        }
    }
}

@MainActor
private func isGitHubUnavailable(_ model: ProjectWindowModel) -> Bool {
    model.snapshot?.connections.first { $0.id == "github" }?.state == .unavailable
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

struct GeneralPane: View {
    @Bindable var model: ProjectWindowModel
    @AppStorage(PreferenceKey.showSamples) private var showSamples = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PaneTitle("General", scope: .everyProject)
            Toggle("Show sample projects in the project picker", isOn: $showSamples)
                .padding(.top, 16)
            Text("Dev Desk \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")")
                .font(DeskFont.secondary)
                .foregroundStyle(DeskColor.mutedInk)
                .padding(.top, 10)

            SectionLabel("Diagnostics").padding(.top, 22)
            HStack(spacing: 10) {
                Button("Run dev doctor") {
                    model.dismissSheet()
                    model.runDoctor()
                }
                .buttonStyle(DeskButtonStyle(kind: .secondary, size: .small))
                .disabled(!model.canRunDoors)
                Text(model.canRunDoors
                     ? "Opens a terminal at the project root and runs the CLI's own check of this machine and this repository."
                     : "A sample project has no folder, so there is nothing to check.")
                    .font(DeskFont.secondary)
                    .foregroundStyle(DeskColor.mutedInk)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: 700, alignment: .leading)
            .padding(.top, 10)
        }
    }
}

struct AppearancePane: View {
    @AppStorage(PreferenceKey.appearance) private var appearance = AppearanceChoice.system
    @AppStorage(PreferenceKey.appIcon) private var appIcon = AppIconChoice.system
    @AppStorage(PreferenceKey.terminalFontSize) private var terminalFontSize = 12.0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PaneTitle("Appearance", scope: .everyProject)
            SettingsRow("Appearance") {
                Picker("", selection: $appearance) {
                    ForEach(AppearanceChoice.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 220)
            }
            .padding(.top, 16)
            SettingsRow("App icon") {
                HStack(spacing: 12) {
                    Picker("", selection: $appIcon) {
                        ForEach(AppIconChoice.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 220)
                    // The artwork the choice resolves to, so both icons are visible while choosing.
                    // Keyed on both preferences so a System choice repaints when Appearance changes.
                    if let preview = AppIconStyle.resolvedImage() {
                        Image(nsImage: preview)
                            .resizable()
                            .interpolation(.high)
                            .frame(width: 64, height: 64)
                            .id("\(appIcon.rawValue)-\(appearance.rawValue)")
                    }
                }
            }
            .padding(.top, 12)
            // Both preferences feed the resolution, so either changing re-applies the icon. System's
            // OS-driven case is re-applied by the effectiveAppearance observer in QuitGuard.
            .onChange(of: appIcon) { AppIconStyle.apply() }
            .onChange(of: appearance) { AppIconStyle.apply() }
            SettingsRow("Terminal text size") {
                Picker("", selection: $terminalFontSize) {
                    ForEach(Array(stride(from: 11.0, through: 14.0, by: 1.0)), id: \.self) { size in
                        Text("\(Int(size)) pt").tag(size)
                    }
                }
                .labelsHidden()
                .frame(width: 120)
            }
            .padding(.top, 12)
        }
    }
}

struct AgentsAndDefaultsPane: View {
    @Bindable var model: ProjectWindowModel
    @AppStorage(PreferenceKey.defaultConnection) private var defaultConnection = AgentDefaults.connection
    @AppStorage(PreferenceKey.runMode) private var runMode = AgentDefaults.runMode
    @AppStorage(PreferenceKey.backgroundConnection) private var storedBackground = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PaneTitle("Agents and defaults", scope: .everyProject)

            SettingsRow("App default connection") {
                Picker("", selection: $defaultConnection) {
                    ForEach(providers, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
                .frame(width: 200)
            }
            .padding(.top, 16)

            SettingsRow("Background runs") {
                Picker("", selection: Binding(
                    get: { BackgroundConnection.resolve(stored: storedBackground, defaultConnection: defaultConnection) },
                    set: { storedBackground = $0 })) {
                    ForEach(BackgroundConnection.choices, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
                .frame(width: 200)
            }
            .padding(.top, 12)
            // Said beside the picker, because the reason it is a second setting is not visible anywhere else.
            Text("Tasks and doors run in a terminal with the default connection, any of the five. Background runs — Findings or Ideation in the background, filing an issue, a diagram — need a headless form this app reads, which only Claude and Codex have.")
                .font(DeskFont.secondary)
                .foregroundStyle(DeskColor.mutedInk)
                .lineSpacing(4)
                .frame(maxWidth: 700, alignment: .leading)
                .padding(.top, 8)

            SettingsRow("App default mode") {
                Picker("", selection: $runMode) {
                    ForEach(RunMode.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .frame(width: 200)
            }
            .padding(.top, 12)

            // Says what the mode above actually means, so it is never a name with no meaning. Both settings are
            // the app's now — a per-project override was a second place to look for what a run would start, and
            // the answer was never found there first. Either picker is free to change while work runs; a new
            // value applies to the next start, never to one already going.
            Text(RunModeChoice.current(for: model.ref).detail)
                .font(DeskFont.secondary)
                .foregroundStyle(DeskColor.mutedInk)
                .lineSpacing(4)
                .frame(maxWidth: 700, alignment: .leading)
                .padding(.top, 10)

            SectionLabel("Capabilities of the selected connection").padding(.top, 18)
            capabilitiesTable.padding(.top, 8)
            // The models sentence used to be a section of its own, whose whole content was that it had none.
            Text([model.snapshot?.capabilities.note,
                  "Models are listed by the connected tool at runtime; Dev Desk stores no version names or pricing."]
                .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " "))
                .font(DeskFont.secondary)
                .foregroundStyle(DeskColor.mutedInk)
                .lineSpacing(4)
                .frame(maxWidth: 700, alignment: .leading)
                .padding(.top, 10)

            if isGitHubUnavailable(model) {
                GitHubUnavailableNotice().padding(.top, 18)
            }
        }
    }

    /// Every agent a task can start with, installed or not: the start sheet says which are missing.
    private var providers: [String] { AgentLaunch.runnableKinds.map(AgentLaunch.connectionName) }

    private var capabilitiesTable: some View {
        let matrix = model.snapshot?.capabilities
        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text("Capability").frame(maxWidth: .infinity, alignment: .leading)
                ForEach(matrix?.providers ?? [], id: \.self) { provider in
                    Text(provider).frame(width: 110, alignment: .leading)
                }
            }
            .font(.system(size: 11.5))
            .foregroundStyle(DeskColor.mutedInk)
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(DeskColor.headerFill)

            ForEach(Array((matrix?.rows ?? []).enumerated()), id: \.element.id) { index, row in
                if index > 0 { Rectangle().fill(DeskColor.rowDivider).frame(height: 1) }
                HStack(spacing: 0) {
                    Text(row.name).frame(maxWidth: .infinity, alignment: .leading)
                    ForEach(Array(row.values.enumerated()), id: \.offset) { _, value in
                        Text(value.rawValue)
                            .foregroundStyle(color(for: value))
                            .frame(width: 110, alignment: .leading)
                    }
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
            }
        }
        .background(DeskColor.surface, in: RoundedRectangle(cornerRadius: DeskMetric.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: DeskMetric.cardRadius).strokeBorder(DeskColor.border))
    }

    private func color(for value: CapabilityValue) -> Color {
        switch value {
        case .yes: return DeskColor.tone(.running).foreground
        case .sometimes: return DeskColor.tone(.waiting).dot
        case .no: return DeskColor.tone(.failed).dot
        case .unknown, .notValidated: return DeskColor.faintInk
        }
    }
}

struct AccountsPane: View {
    @Bindable var model: ProjectWindowModel
    @State private var signingOut: Connection?
    /// Set when Automation was refused and the command went to the clipboard instead, so the pane says so
    /// rather than appearing to do nothing.
    @State private var copied: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PaneTitle("Accounts and connections", scope: .everyProject)

            VStack(alignment: .leading, spacing: 10) {
                ForEach(model.snapshot?.connections ?? []) { connection in
                    row(connection)
                }
            }
            .padding(.top, 16)

            if let copied { copiedNotice(copied) }

            Text(model.snapshot?.connectionsNote ?? "")
                .font(DeskFont.secondary)
                .foregroundStyle(DeskColor.mutedInk)
                .lineSpacing(4)
                .frame(maxWidth: 700, alignment: .leading)
                .padding(.top, 12)

            if let account = model.snapshot?.projectFacts.first(where: { $0.key == "GitHub account" }) {
                KeyValueTable(rows: [account]).padding(.top, 16)
            }

            if isGitHubUnavailable(model) {
                GitHubUnavailableNotice().padding(.top, 16)
            }
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

    /// One connection: what it is, who it is, and the one action it has. The app never sees a credential —
    /// it types the tool's own command into a terminal at the project root (decision 14).
    private func row(_ connection: Connection) -> some View {
        HStack(spacing: 8) {
            StatusDot(tone: tone(for: connection.state))
            Text(connection.name)
            Spacer(minLength: 8)
            Text(connection.label)
                .foregroundStyle(connection.isSignedOut ? DeskColor.tone(.failed).dot : DeskColor.mutedInk)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(connection.detail ?? connection.label)
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
            }
        }
    }

    /// Automation was refused, so the command is on the clipboard. Its own view: inlining the interpolation
    /// in `body` pushed this pane past what the type-checker would solve.
    private func copiedNotice(_ command: String) -> some View {
        let message = "Couldn't open your terminal, so `" + command
            + "` is on the clipboard — paste it into a terminal to finish."
        return Text(message)
            .font(DeskFont.secondary)
            .foregroundStyle(DeskColor.tone(.waiting).foreground)
            .padding(.top, 12)
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

struct NotificationsPane: View {
    @AppStorage(PreferenceKey.notifyDecisions) private var notifyDecisions = true
    @AppStorage(PreferenceKey.notifyCompletion) private var notifyCompletion = true
    @AppStorage(PreferenceKey.notifyFailures) private var notifyFailures = true
    @AppStorage(PreferenceKey.notifySound) private var sound = NotificationSound.defaultName

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PaneTitle("Notifications", scope: .everyProject)
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Decisions that need you", isOn: $notifyDecisions)
                Toggle("Completed work", isOn: $notifyCompletion)
                Toggle("Failed runs", isOn: $notifyFailures)
            }
            .padding(.top, 16)
            SettingsRow("Sound") {
                HStack(spacing: 8) {
                    Picker("", selection: $sound) {
                        Text("None").tag("")
                        ForEach(NotificationSound.choices, id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: 160)
                    Button("Preview") { NotificationSound.play(sound) }
                        .buttonStyle(DeskButtonStyle(kind: .secondary, size: .small))
                        .disabled(sound.isEmpty)
                }
            }
            .padding(.top, 14)
            Text("Background runs and terminal sessions both notify. Claude and Codex report exactly when they need you or finish a turn; other tools are heard through the terminal bell, which only guesses. The sound plays even when the session is already on screen.")
                .font(DeskFont.secondary)
                .foregroundStyle(DeskColor.mutedInk)
                .lineSpacing(4)
                .padding(.top, 12)
        }
    }
}

struct ExecutionPane: View {
    @AppStorage(PreferenceKey.worktreeLocation) private var worktreeLocation = AgentDefaults.worktreeLocation
    @AppStorage(PreferenceKey.agentLimit) private var agentLimit = AgentLimit.defaultValue
    @AppStorage(PreferenceKey.confirmQuit) private var confirmQuit = true
    @AppStorage(PreferenceKey.autoReload) private var autoReload = false
    @AppStorage(PreferenceKey.runMaxAgents) private var runMaxAgents = RunStops.defaultMaxAgents

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PaneTitle("Execution", scope: .everyProject)
            SettingsRow("Parallel task checkouts") {
                HStack(spacing: 8) {
                    TextField("", text: $worktreeLocation)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 10)
                        .frame(width: 260, height: 28)
                        .background(DeskColor.surface, in: RoundedRectangle(cornerRadius: DeskMetric.controlRadius))
                        .overlay(RoundedRectangle(cornerRadius: DeskMetric.controlRadius)
                            .strokeBorder(pathProblem == nil ? DeskColor.controlBorder : DeskColor.tone(.failed).dot))
                    Button("Choose…") { chooseFolder() }
                        .buttonStyle(DeskButtonStyle(kind: .secondary, size: .small))
                }
            }
            .padding(.top, 16)
            // A typo used to surface much later, as a git error when a session tried to start in it.
            Text(pathProblem ?? "Task worktrees are created here when you start a shell or an agent for a task that isn't checked out yet, including a detached one for a task with no branch.")
                .font(DeskFont.secondary)
                .foregroundStyle(pathProblem == nil ? DeskColor.mutedInk : DeskColor.tone(.failed).dot)
                .lineSpacing(4)
                .frame(maxWidth: 700, alignment: .leading)
                .padding(.top, 12)
            Stepper(value: $agentLimit, in: AgentLimit.range) {
                Text(agentLimit == 1 ? "Run at most 1 agent at once" : "Run at most \(agentLimit) agents at once")
            }
            .fixedSize()
            .padding(.top, 16)
            Stepper(value: $runMaxAgents, in: RunStops.maxAgentsRange, step: 5) {
                Text("A findings or ideation run may start at most \(runMaxAgents) agents")
            }
            .fixedSize()
            .padding(.top, 16)
            Text("Finders and checkers together. A run whose plan needs more starts nothing and says why.")
                .font(DeskFont.secondary)
                .foregroundStyle(DeskColor.mutedInk)
                .lineSpacing(4)
                .padding(.top, 8)
            Toggle("Reload every 2 minutes", isOn: $autoReload)
                .padding(.top, 16)
            Text("Off, the board is read again when you act — opening, ⌘R, a start, a stop, a move — and each of those first pulls from origin. The timed reload never pulls.")
                .font(DeskFont.secondary)
                .foregroundStyle(DeskColor.mutedInk)
                .lineSpacing(4)
                .padding(.top, 8)
            Toggle("Ask before quitting while something is running", isOn: $confirmQuit)
                .padding(.top, 16)
            Text("Quitting ends every session and background run. The question is only ever asked when one of them is live.")
                .font(DeskFont.secondary)
                .foregroundStyle(DeskColor.mutedInk)
                .lineSpacing(4)
                .padding(.top, 8)
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

struct ProjectOverridesPane: View {
    @Bindable var model: ProjectWindowModel

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
        VStack(alignment: .leading, spacing: 0) {
            PaneTitle("Project overrides", scope: .thisProject)
            // Two different things sat under one caption: facts the repository owns, and preferences Dev Desk
            // owns. The caption spoke for the first and denied the second, which was sitting right below it.
            SectionLabel("From the repository").padding(.top, 18)
            KeyValueTable(rows: model.snapshot?.projectFacts ?? [])
                .padding(.top, 8)
            Text("Read from the repository. Dev Desk never overrides the repository's own configuration.")
                .font(DeskFont.secondary)
                .foregroundStyle(DeskColor.mutedInk)
                .lineSpacing(4)
                .padding(.top, 10)
            // Auto applies to local projects only.
            if !model.ref.isSample {
                SectionLabel("Dev Desk, for this project").padding(.top, 20)
                Text("Kept on this Mac, not in the repository.")
                    .font(DeskFont.secondary)
                    .foregroundStyle(DeskColor.mutedInk)
                    .padding(.top, 6)
                AutoModeSetting(ref: model.ref)
                    .padding(.top, 12)

                SectionLabel("Cleanup").padding(.top, 20)
                HStack(spacing: 10) {
                    Button("Reset findings…") {
                        model.dismissSheet()
                        model.present(.resetFindings)
                    }
                    .buttonStyle(DeskButtonStyle(kind: .secondary, size: .small))
                    Text(resetSummary)
                        .font(DeskFont.secondary)
                        .foregroundStyle(DeskColor.mutedInk)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: 700, alignment: .leading)
                .padding(.top, 10)
            }
        }
    }
}

/// This project's Auto. Turning it on asks first, since it spends tokens unattended; Cancel leaves it off.
private struct AutoModeSetting: View {
    @AppStorage private var autoMode: Bool
    @AppStorage(PreferenceKey.agentLimit) private var agentLimit = AgentLimit.defaultValue
    @State private var confirming = false

    init(ref: ProjectRef) {
        _autoMode = AppStorage(wrappedValue: false, PreferenceKey.autoMode(ref))
    }

    var body: some View {
        let notice = AutoAgents.notice(limit: min(max(agentLimit, AgentLimit.range.lowerBound), AgentLimit.range.upperBound))
        VStack(alignment: .leading, spacing: 0) {
            Toggle("Auto", isOn: Binding(get: { autoMode }, set: { isOn in
                if isOn { confirming = true } else { autoMode = false }
            }))
            Text(verbatim: notice)
                .font(DeskFont.secondary)
                .foregroundStyle(DeskColor.mutedInk)
                .lineSpacing(4)
                .frame(maxWidth: 700, alignment: .leading)
                .padding(.top, 8)
        }
        .alert(Text(verbatim: notice), isPresented: $confirming) {
            Button("Turn on Auto") { autoMode = true }
            Button("Cancel", role: .cancel) {}
        }
    }
}

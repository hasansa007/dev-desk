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
    @AppStorage(PreferenceKey.showSamples) private var showSamples = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("General").font(DeskFont.section)
            Toggle("Show sample projects in the project picker", isOn: $showSamples)
                .padding(.top, 16)
            Text("Dev Desk \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")")
                .font(DeskFont.secondary)
                .foregroundStyle(DeskColor.mutedInk)
                .padding(.top, 10)
        }
    }
}

struct AppearancePane: View {
    @AppStorage(PreferenceKey.appearance) private var appearance = AppearanceChoice.system
    @AppStorage(PreferenceKey.terminalFontSize) private var terminalFontSize = 12.0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Appearance").font(DeskFont.section)
            SettingsRow("Appearance") {
                Picker("", selection: $appearance) {
                    ForEach(AppearanceChoice.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 220)
            }
            .padding(.top, 16)
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
    @AppStorage(PreferenceKey.defaultConnection) private var defaultConnection = "Codex"

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Agents and defaults").font(DeskFont.section)

            SettingsRow("App default connection") {
                Picker("", selection: $defaultConnection) {
                    ForEach(providers, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
                .frame(width: 200)
            }
            .padding(.top, 16)

            SettingsRow("\(projectName) override") {
                Picker("", selection: overrideBinding) {
                    Text("Use app default").tag("")
                    ForEach(providers, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
                .frame(width: 200)
            }
            .padding(.top, 12)

            SectionLabel("Capabilities of the selected connection").padding(.top, 18)
            capabilitiesTable.padding(.top, 8)
            Text(model.snapshot?.capabilities.note ?? "")
                .font(DeskFont.secondary)
                .foregroundStyle(DeskColor.mutedInk)
                .lineSpacing(4)
                .frame(maxWidth: 700, alignment: .leading)
                .padding(.top, 10)

            SectionLabel("Available models").padding(.top, 18)
            Text("Model choices are listed by the connected tool at runtime. Dev Desk does not store version names or pricing.")
                .foregroundStyle(DeskColor.secondaryInk)
                .lineSpacing(4)
                .padding(.top, 8)

            if isGitHubUnavailable(model) {
                GitHubUnavailableNotice().padding(.top, 18)
            }
        }
    }

    private var providers: [String] { model.snapshot?.capabilities.providers ?? [] }
    private var projectName: String { model.snapshot?.project.name ?? model.ref.displayName }

    private var overrideBinding: Binding<String> {
        let key = PreferenceKey.connectionOverride(model.ref)
        return Binding(get: { UserDefaults.standard.string(forKey: key) ?? "" },
                        set: { UserDefaults.standard.set($0, forKey: key) })
    }

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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Accounts and connections").font(DeskFont.section)

            VStack(alignment: .leading, spacing: 10) {
                ForEach(model.snapshot?.connections ?? []) { connection in
                    HStack(spacing: 8) {
                        StatusDot(tone: tone(for: connection.state))
                        Text(connection.name)
                        Spacer(minLength: 8)
                        Text(connection.label).foregroundStyle(DeskColor.mutedInk)
                    }
                }
            }
            .padding(.top, 16)

            if let account = model.snapshot?.projectFacts.first(where: { $0.key == "GitHub account" }) {
                KeyValueTable(rows: [account]).padding(.top, 16)
            }

            if isGitHubUnavailable(model) {
                GitHubUnavailableNotice().padding(.top, 16)
            }
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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Notifications").font(DeskFont.section)
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Decisions that need you", isOn: $notifyDecisions)
                Toggle("Completed work", isOn: $notifyCompletion)
                Toggle("Failed runs", isOn: $notifyFailures)
            }
            .padding(.top, 16)
            Text("Notifications apply to managed work, which Dev Desk doesn't run yet. Your choices are kept for when it does.")
                .font(DeskFont.secondary)
                .foregroundStyle(DeskColor.mutedInk)
                .lineSpacing(4)
                .padding(.top, 12)
        }
    }
}

struct ExecutionPane: View {
    @AppStorage(PreferenceKey.worktreeLocation) private var worktreeLocation = "~/.devdesk/wt"

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Execution").font(DeskFont.section)
            SettingsRow("Parallel task checkouts") {
                HStack(spacing: 8) {
                    TextField("", text: $worktreeLocation)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 10)
                        .frame(width: 260, height: 28)
                        .background(DeskColor.surface, in: RoundedRectangle(cornerRadius: DeskMetric.controlRadius))
                        .overlay(RoundedRectangle(cornerRadius: DeskMetric.controlRadius).strokeBorder(DeskColor.controlBorder))
                    Button("Choose…") { chooseFolder() }
                        .buttonStyle(DeskButtonStyle(kind: .secondary, size: .small))
                }
            }
            .padding(.top, 16)
            Text("Task worktrees are created here when you start a shell for a branch that isn't checked out.")
                .font(DeskFont.secondary)
                .foregroundStyle(DeskColor.mutedInk)
                .lineSpacing(4)
                .padding(.top, 12)
        }
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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Project overrides").font(DeskFont.section)
            KeyValueTable(rows: model.snapshot?.projectFacts ?? [])
                .padding(.top, 16)
            Text("Read from the repository. Dev Desk never overrides the repository's own configuration.")
                .font(DeskFont.secondary)
                .foregroundStyle(DeskColor.mutedInk)
                .lineSpacing(4)
                .padding(.top, 12)
        }
    }
}

import DeskCore
import SwiftUI

/// The project, drawn: the five kinds `dev:arch` can draw down the left, the one you chose filling the rest.
/// A kind that has been drawn shows its newest HTML from `docs/arch/`; a kind that has not offers to generate
/// it. Generating runs `dev:arch` in the background — a session in Sessions, without leaving this screen — and
/// the kind's pane swaps from a spinner to the drawing the moment its file lands. The app lists and shows what
/// the door drew; it never draws one itself.
struct DiagramsScreen: View {
    @Bindable var model: ProjectWindowModel
    /// Read so a change to the default connection re-resolves the agent, the same way the starter's composer does.
    @AppStorage(PreferenceKey.defaultConnection) private var defaultConnection = AgentDefaults.connection
    @AppStorage(PreferenceKey.backgroundConnection) private var storedBackground = ""
    @AppStorage(PreferenceKey.worktreeLocation) private var worktreeLocation = AgentDefaults.worktreeLocation
    @Environment(\.terminals) private var terminals
    @State private var selectedKind = ArchDiagrams.kinds.first ?? "architecture"
    @State private var target = ""
    /// The GitHub URL typed into the no-remote setup, so Archify has an `owner/repo` to validate against.
    @State private var remoteURL = ""

    /// The agent a generate runs, resolved the way every other screen resolves it — the saved default connection,
    /// validated against this project's detected connections — rather than a raw preference string that fell back
    /// to Codex. `_ = defaultConnection` keeps the view re-resolving when the default changes.
    /// A generate is a background run, so it uses the Background runs setting, never a terminal-only default.
    private var agentName: String? {
        let name = BackgroundConnection.resolve(stored: storedBackground, defaultConnection: defaultConnection)
        guard case .ready(let agent) = AgentChoice.resolve(override: "", defaultConnection: name,
                                                           connections: model.snapshot?.connections ?? []) else { return nil }
        return AgentLaunch.connectionName(agent)
    }

    private var repositoryRoot: String? { model.snapshot?.repositoryRoot }
    /// The newest file for the selected kind, re-read whenever the project reloads (a finished generate reloads).
    private var selectedDiagram: ArchDiagram? {
        _ = model.lastLoadedAt
        return model.diagram(kind: selectedKind)
    }

    var body: some View {
        HStack(spacing: 0) {
            kindRail
            VStack(spacing: 0) {
                header
                pane
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(DeskColor.canvas)
    }

    // MARK: - Rail

    /// The five kinds, always — a kind is a place to generate into, not only a file to show. Each says whether
    /// it has been drawn, is being drawn now, or has not been drawn yet.
    private var kindRail: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Diagrams")
                .font(DeskFont.body.weight(.semibold))
                .foregroundStyle(DeskColor.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 12))
                .overlay(alignment: .bottom) { Rectangle().fill(DeskColor.divider).frame(height: 1) }

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(ArchDiagramKind.all) { kind in
                        kindRow(kind)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(width: 248, alignment: .leading)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(DeskColor.surface)
        .overlay(alignment: .trailing) { Rectangle().fill(DeskColor.divider).frame(width: 1) }
    }

    @ViewBuilder private func kindRow(_ kind: ArchDiagramKind) -> some View {
        let isSelected = selectedKind == kind.token
        let existing = model.diagram(kind: kind.token)
        let isGenerating = model.isGeneratingDiagram(kind: kind.token)
        Button { selectedKind = kind.token } label: {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(kind.title)
                        .font(DeskFont.secondary)
                        .foregroundStyle(DeskColor.ink)
                        .lineLimit(1)
                    Text(kindSubtitle(existing: existing, generating: isGenerating))
                        .font(DeskFont.mono(11))
                        .foregroundStyle(DeskColor.faintInk)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                if isGenerating {
                    ProgressView().controlSize(.small)
                } else if existing != nil {
                    Circle().fill(DeskColor.tone(.running).dot).frame(width: 6, height: 6)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(EdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 12))
            .background(isSelected ? DeskColor.tone(.info).fill : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func kindSubtitle(existing: ArchDiagram?, generating: Bool) -> String {
        if generating { return "Generating…" }
        if let existing { return existing.url.lastPathComponent }
        return "Not generated"
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "rectangle.3.group")
                .foregroundStyle(DeskColor.accent)
                .frame(width: 28, height: 28)
                .background(DeskColor.tone(.info).fill, in: RoundedRectangle(cornerRadius: DeskMetric.controlRadius))
            VStack(alignment: .leading, spacing: 1) {
                Text(selectedTitle).font(DeskFont.section).foregroundStyle(DeskColor.ink)
                Text("Architecture diagrams for this project")
                    .font(DeskFont.secondary)
                    .foregroundStyle(DeskColor.mutedInk)
            }
            Spacer(minLength: 8)
            // Regenerate is offered only when this kind already has a drawing to replace; a kind with none
            // shows Generate in its pane instead. Both run the same background dev:arch for this kind.
            if selectedDiagram != nil {
                Button("Regenerate") { generate() }
                    .buttonStyle(DeskButtonStyle(kind: .secondary, size: .small))
                    .disabled(blockedReason != nil)
                    .help(blockedReason ?? "Runs dev:arch again to redraw this \(selectedTitle) diagram")
            }
        }
        .padding(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
        .background(DeskColor.surface)
        .overlay(alignment: .bottom) { Rectangle().fill(DeskColor.divider).frame(height: 1) }
    }

    private var selectedTitle: String {
        ArchDiagramKind.all.first { $0.token == selectedKind }?.title ?? "Diagram"
    }

    // MARK: - Pane

    @ViewBuilder private var pane: some View {
        if model.isGeneratingDiagram(kind: selectedKind) {
            generatingPane
        } else if let diagram = selectedDiagram {
            WebView(file: diagram.url)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            generatePane
        }
    }

    /// The kind's run is in flight: a spinner, and a word about where it is running. It stays here until the
    /// file lands, then the pane becomes the drawing on the next reload.
    private var generatingPane: some View {
        VStack(spacing: 12) {
            Spacer(minLength: 0)
            ProgressView().controlSize(.large)
            Text("Generating the \(selectedTitle) diagram…")
                .font(DeskFont.body)
                .foregroundStyle(DeskColor.ink)
            Text("dev:arch is drawing this in the background — it appears in Sessions, and lands here when it finishes.")
                .font(DeskFont.secondary)
                .foregroundStyle(DeskColor.mutedInk)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    /// Nothing drawn for this kind yet: say what it is and offer to generate it, with an optional target so a
    /// kind can be scoped to a subsystem rather than the whole project. When the last run drew nothing, the
    /// reason leads instead of the plain "no diagram yet" note, so a refusal is visible rather than a mystery.
    private var generatePane: some View {
        VStack {
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 12) {
                // Only where it blocks: dev:arch draws from committed code, so a folder that is not a repo, or
                // one with no commits, cannot be drawn. Offer the setup step instead of a Generate that fails.
                switch model.diagramRepoState {
                case .notARepository: repoSetupContent
                case .noCommits: needsCommitContent
                case .noRemote: needsRemoteContent
                case .ready: drawContent
                }
            }
            .frame(maxWidth: 560)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    /// The ordinary state: offer to draw this kind, with an optional target. A failed earlier run leads with
    /// what it actually printed — its own last words, then the timing's verdict — so a swallowed launch reads
    /// as one instead of as a guess about declining, and its kept session is one click away.
    @ViewBuilder private var drawContent: some View {
        let blocked = blockedReason
        let failure = model.diagramGenerateFailure(kind: selectedKind)
        if let failure {
            NoticeBanner(tone: .waiting, title: "No \(selectedTitle) diagram was drawn", message: failure.message) {
                if let sessionID = failure.sessionID {
                    Button("Open the run") { openRun(sessionID) }
                        .buttonStyle(DeskButtonStyle(kind: .secondary, size: .small))
                        .help("Opens the run's session in Sessions, where its full transcript is kept")
                }
            }
            if !failure.outputTail.isEmpty {
                failureOutput(failure.outputTail)
            }
        } else {
            NoticeBanner(tone: .neutral, title: "No \(selectedTitle) diagram yet",
                         message: "dev:arch draws this project and writes each diagram to docs/arch/ as a standalone HTML file. Generate it, and it appears here.")
        }
        if let blocked {
            NoticeBanner(tone: .neutral, title: "Nothing to run here", message: blocked, style: .compact)
        }
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("What to draw")
            TextField("What to draw — e.g. the auth flow, or web/app/lib. Leave empty to draw the whole project.",
                      text: $target)
                .textFieldStyle(.plain)
                .font(DeskFont.body)
                .padding(.horizontal, 10)
                .controlChrome(height: 28)
        }
        HStack(spacing: 8) {
            Spacer(minLength: 0)
            Button(failure == nil ? "Generate \(selectedTitle)" : "Try again") { generate() }
                .buttonStyle(DeskButtonStyle(kind: .primary, size: .small))
                .disabled(blocked != nil)
        }
    }

    /// The folder is not a git repository. dev:arch pins nodes to a real commit, so it needs one — the app does
    /// not create it for you; it says what to do and leaves git to you.
    @ViewBuilder private var repoSetupContent: some View {
        NoticeBanner(tone: .neutral, title: "This folder isn't a git repository",
                     message: "dev:arch draws from committed code — it pins each node to a real commit. Make this a git repository with a commit and a GitHub remote (git init, commit, and git remote add origin …), then generate.")
    }

    /// The folder is a repo with no commits. dev:arch needs one to pin to; the app does not commit your files
    /// for you — it says what is needed and leaves the commit to you.
    @ViewBuilder private var needsCommitContent: some View {
        NoticeBanner(tone: .waiting, title: "This repository has no commits yet",
                     message: "dev:arch draws from committed code, so it needs at least one commit to pin to. Commit your files — e.g. git add -A && git commit -m \"initial commit\" — then generate this diagram.")
    }

    /// The repo has a commit but no `origin` remote. Archify's schema requires `meta.repository.url` to be a
    /// GitHub URL (`^https://github.com/owner/repo`), so a diagram cannot validate without one. Ask for the URL
    /// — nothing is pushed — then add the remote and draw. This is the renderer's requirement, not the app's.
    @ViewBuilder private var needsRemoteContent: some View {
        NoticeBanner(tone: .waiting, title: "This repository has no GitHub remote",
                     message: "Archify (the renderer) validates every diagram against a GitHub repository URL, so it needs an origin remote to pin to. Add the repo's GitHub URL below — nothing is pushed — then the diagram can be drawn.")
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("GitHub URL")
            TextField("https://github.com/owner/repo", text: $remoteURL)
                .textFieldStyle(.plain)
                .font(DeskFont.body)
                .padding(.horizontal, 10)
                .controlChrome(height: 28)
        }
        HStack(spacing: 8) {
            Spacer(minLength: 0)
            Button("Add remote & generate \(selectedTitle)") { addRemoteAndGenerate() }
                .buttonStyle(DeskButtonStyle(kind: .primary, size: .small))
                .disabled(blockedReason != nil || !isGitHubURL(remoteURL))
        }
    }

    /// The shape Archify's schema accepts: `https://github.com/owner/repo` (optionally `.git`). Checked here so
    /// the button only offers a URL that will actually validate, rather than adding a remote that still fails.
    private func isGitHubURL(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .range(of: #"^https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+(?:\.git)?/?$"#, options: .regularExpression) != nil
    }

    /// The last lines the failed run wrote, as it wrote them — monospaced, newest last, straight from the
    /// session's buffer. The banner above summarises; this is the evidence itself, in the same dress the
    /// recovered-run rows give a log tail.
    private func failureOutput(_ lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(Array(lines.suffix(6).enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(DeskFont.mono(11))
                    .foregroundStyle(DeskColor.secondaryInk)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(DeskColor.surface, in: RoundedRectangle(cornerRadius: DeskMetric.controlRadius))
        .overlay(RoundedRectangle(cornerRadius: DeskMetric.controlRadius).strokeBorder(DeskColor.border))
    }

    /// The kept session of a failed generate, selected in Sessions: the tab opens on the ended terminal, whose
    /// pane shows the run's exit status and last output.
    private func openRun(_ sessionID: String) {
        model.selectedSessionID = sessionID
        model.go(.terminals)
    }

    // MARK: - Actions

    private var blockedReason: String? {
        guard let agentName else {
            return "No agent is available. Choose Claude or Codex in Settings."
        }
        return model.diagramGenerateBlockedReason(kind: selectedKind, agent: agentName)
    }

    private func generate() {
        guard let terminals, let agentName else { return }
        model.generateDiagram(kind: selectedKind, target: target.trimmingCharacters(in: .whitespacesAndNewlines),
                              agent: agentName, terminals: terminals, worktreeLocation: worktreeLocation)
    }

    /// One tap from a repo with no remote to a drawn diagram: add the GitHub origin the user typed, and only if
    /// the remote now exists, start the generate. If adding it did not take, the pane stays on the no-remote
    /// guidance rather than starting a run Archify will still reject for a missing repository URL.
    private func addRemoteAndGenerate() {
        Task {
            if await model.addGitRemote(url: remoteURL) { generate() }
        }
    }
}

/// The five diagram kinds `dev:arch` draws, in the skill's own order: the title reads, the token is the argument.
private struct ArchDiagramKind: Identifiable {
    let token: String
    let title: String
    var id: String { token }

    static let all = [
        ArchDiagramKind(token: "architecture", title: "Architecture"),
        ArchDiagramKind(token: "workflow", title: "Workflow"),
        ArchDiagramKind(token: "dataflow", title: "Data flow"),
        ArchDiagramKind(token: "sequence", title: "Sequence"),
        ArchDiagramKind(token: "lifecycle", title: "Lifecycle"),
    ]
}

struct DiagramsScreen_Previews: PreviewProvider {
    static var previews: some View {
        PreviewHost().frame(width: 1180, height: 800)
    }

    private struct PreviewHost: View {
        @State private var model = ProjectWindowModel(ref: .sample(.studyHub), source: SampleDataSource(project: .studyHub))

        var body: some View {
            DiagramsScreen(model: model)
                .task {
                    await model.load()
                    model.go(.diagrams)
                }
        }
    }
}

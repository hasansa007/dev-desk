import DeskCore
import SwiftUI

/// The project, drawn (ADR 0047): three kinds as chips under the header — Architecture, Data flow, Sequence.
/// Architecture and Data flow are one drawing each of the whole project. Sequence is one drawing per flow, and
/// its flows are listed down the left from whichever source this project has. A drawn one shows its newest HTML
/// from `docs/arch/`; one that is not offers to generate it. Generating runs `dev:arch` in the background — a session in Sessions, without leaving this screen — and
/// the kind's pane swaps from a spinner to the drawing the moment its file lands. The app lists and shows what
/// the door drew; it never draws one itself.
struct DiagramsScreen: View {
    @Bindable var model: ProjectWindowModel
    /// Read so a change to the default connection re-resolves the agent, the same way the starter's composer does.
    @AppStorage(PreferenceKey.defaultConnection) private var defaultConnection = AgentDefaults.connection
    @AppStorage(PreferenceKey.backgroundConnection) private var storedBackground = ""
    @AppStorage(PreferenceKey.worktreeLocation) private var worktreeLocation = AgentDefaults.worktreeLocation
    @Environment(\.terminals) private var terminals
    /// The chip and the Sequence flow live on the model, so switching tabs keeps them.
    private var selectedKind: String {
        get { model.diagramKind }
        nonmutating set { model.diagramKind = newValue }
    }
    private var selectedFlow: String? {
        get { model.diagramFlow }
        nonmutating set { model.diagramFlow = newValue }
    }
    /// A flow typed into "Name a flow" and being drawn: no source names it yet, so it is listed from here until
    /// its drawing lands and lists it as drawn.
    @State private var typedFlow: SequenceFlow?
    @State private var newFlowName = ""
    @State private var isNamingFlow = false
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
        if isSequence { return currentFlow?.drawing ?? currentFlow.flatMap { model.diagram(kind: $0.generateKey) } }
        return model.diagram(kind: selectedKind)
    }

    private var isSequence: Bool { selectedKind == "sequence" }

    /// Every flow Sequence offers, plus one typed and still being drawn.
    private var flows: [SequenceFlow] {
        _ = model.lastLoadedAt
        var all = model.sequenceFlows
        if let typedFlow, !all.contains(where: { $0.slug == typedFlow.slug }) { all.append(typedFlow) }
        return all
    }

    private var currentFlow: SequenceFlow? {
        let all = flows
        // Nothing chosen yet: open on a flow that has a drawing, not on an empty pane.
        return all.first { $0.slug == selectedFlow } ?? all.first { $0.drawing != nil } ?? all.first
    }

    /// What the selected drawing's run is tracked under: the kind, or on Sequence the flow's key.
    private var selectedKey: String {
        isSequence ? (currentFlow?.generateKey ?? "sequence") : selectedKind
    }

    var body: some View {
        // The shared header spans the tab; the kinds and the drawing sit below it (ADR 0046 decision 14).
        // The shared filter panel (ADR 0046 decision 18): what to draw, and on Sequence which flow.
        HStack(spacing: 0) {
            filterPanel
            VStack(spacing: 0) {
                header
                    .popover(isPresented: $isNamingFlow, arrowEdge: .bottom) { nameFlowForm.padding(14).frame(width: 340) }
                pane.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(DeskColor.canvas)
    }

    // MARK: - Kinds and flows

    private var filterPanel: some View {
        var groups = [FilterGroup(key: "diagrams.draw", title: "Draw", kind: .pickOne,
                                  options: ArchDiagramKind.all.map { kind in
                                      FilterOption(id: kind.token, label: kind.title, isOn: selectedKind == kind.token,
                                                   tone: kindIsDrawn(kind.token) ? .running : nil,
                                                   count: kind.token == "sequence" && !flows.isEmpty
                                                       ? "\(flows.filter { $0.drawing != nil }.count) of \(flows.count)" : nil,
                                                   help: kind.help)
                                  },
                                  toggle: { selectedKind = $0 })]
        if isSequence && !flows.isEmpty {
            groups.append(FilterGroup(key: "diagrams.flow", title: "Flow", kind: .pickOne,
                                      options: flows.map { flow in
                                          let from = flow.sources.sorted().map(\.rawValue).joined(separator: ", ")
                                          return FilterOption(id: flow.slug, label: flow.name, isOn: currentFlow?.slug == flow.slug,
                                                              tone: flow.drawing != nil ? .running : nil,
                                                              help: model.isGeneratingDiagram(kind: flow.generateKey) ? "Drawing…" : "From \(from)")
                                      },
                                      toggle: { selectedFlow = $0 },
                                      footer: ("Draw another flow…", { isNamingFlow = true })))
        }
        return FilterPanel(title: "Drawings", storageKey: "diagrams", groups: groups)
    }

    private func kindIsDrawn(_ token: String) -> Bool {
        token == "sequence" ? flows.contains { $0.drawing != nil } : model.diagram(kind: token) != nil
    }

    /// A flow no source names: typed, listed at once, and drawn.
    private var nameFlowForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Draw another flow").font(DeskFont.body.weight(.semibold))
            HStack(spacing: 8) {
                TextField("A flow — e.g. Sign in, or Checkout", text: $newFlowName)
                    .textFieldStyle(.plain)
                    .font(DeskFont.body)
                    .padding(.horizontal, 10)
                    .controlChrome(height: 28)
                    .onSubmit(drawTypedFlow)
                Button("Draw", action: drawTypedFlow)
                    .buttonStyle(DeskButtonStyle(kind: .primary, size: .small))
                    .disabled(SequenceFlows.slug(newFlowName).isEmpty || blockedReason != nil)
            }
        }
    }

    /// The flow typed in "Draw another flow…": listed at once, selected, and drawn.
    private func drawTypedFlow() {
        let name = newFlowName.trimmingCharacters(in: .whitespacesAndNewlines)
        let slug = SequenceFlows.slug(name)
        guard !slug.isEmpty, blockedReason == nil else { return }
        if !flows.contains(where: { $0.slug == slug }) {
            typedFlow = SequenceFlow(name: name, slug: slug, sources: [])
        }
        selectedFlow = slug
        newFlowName = ""
        isNamingFlow = false
        generate()
    }

    // MARK: - Header

    /// The shared header: the kind on screen and how many are drawn, and Redraw when there is a drawing to replace —
    /// a kind with none offers Generate in its pane. Both run the same background dev:arch for this kind.
    private var header: some View {
        ScreenHeader(.diagrams) {
            Text(headerStatus)
        } tools: {
            if selectedDiagram != nil, !model.isGeneratingDiagram(kind: selectedKey) {
                Button("Redraw") { generate() }
                    .buttonStyle(DeskButtonStyle(kind: .primary, size: .small))
                    .disabled(blockedReason != nil)
                    .help(blockedReason ?? "Runs dev:arch again to redraw this \(selectedTitle) diagram")
            }
        }
    }

    private var headerStatus: String {
        if isSequence {
            guard let flow = currentFlow else { return "Sequence · no flows named yet" }
            return "Sequence · \(flow.name) · " + (flow.drawing?.url.lastPathComponent ?? "not drawn yet")
        }
        guard let drawn = selectedDiagram else { return "\(selectedTitle) · not drawn yet" }
        return "\(selectedTitle) · \(drawn.url.lastPathComponent)"
    }

    /// The kind's name, or on Sequence the flow's.
    private var selectedTitle: String {
        if isSequence, let flow = currentFlow { return flow.name }
        return ArchDiagramKind.all.first { $0.token == selectedKind }?.title ?? "Diagram"
    }

    // MARK: - Pane

    @ViewBuilder private var pane: some View {
        if isSequence && flows.isEmpty {
            noFlowsPane
        } else if model.isGeneratingDiagram(kind: selectedKey) {
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
            Text("dev:arch is drawing this in its session — answer it there, and the drawing lands here as soon as it is written.")
                .font(DeskFont.secondary)
                .foregroundStyle(DeskColor.mutedInk)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
        // The session does not exit when the file is written, so the folder is read again until it lands.
        .task(id: selectedKey) {
            while !Task.isCancelled, model.isGeneratingDiagram(kind: selectedKey) {
                try? await Task.sleep(for: .seconds(4))
                await model.load()
                model.pickUpGeneratedDiagrams()
            }
        }
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
                switch model.diagramRepoState(kind: selectedKind) {
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
        let failure = model.diagramGenerateFailure(kind: selectedKey)
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
            NoticeBanner(tone: .neutral, title: isSequence ? "\(selectedTitle) is not drawn yet" : "No \(selectedTitle) diagram yet",
                         message: isSequence
                            ? "A sequence draws this one flow over time: who calls whom, in order, from where it starts to where it finishes. dev:arch writes it to docs/arch/."
                            : "dev:arch draws this project and writes each diagram to docs/arch/ as a standalone HTML file. Draw it, and it appears here.")
        }
        if let blocked {
            NoticeBanner(tone: .neutral, title: "Nothing to run here", message: blocked, style: .compact)
        }
        // A flow's sequence already says what to draw; the whole-project kinds can still be scoped to a part.
        if !isSequence {
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel("What to draw")
                TextField("What to draw — e.g. the auth part, or web/app/lib. Leave empty to draw the whole project.",
                          text: $target)
                    .textFieldStyle(.plain)
                    .font(DeskFont.body)
                    .padding(.horizontal, 10)
                    .controlChrome(height: 28)
            }
        }
        HStack(spacing: 8) {
            Spacer(minLength: 0)
            Button(failure == nil ? "Draw \(selectedTitle)" : "Try again") { generate() }
                .buttonStyle(DeskButtonStyle(kind: .primary, size: .small))
                .disabled(blocked != nil)
        }
    }

    /// Sequence with no flow named anywhere yet. Any one source is enough, and none is required: name one here.
    private var noFlowsPane: some View {
        VStack {
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 12) {
                NoticeBanner(tone: .neutral, title: "No flows named yet",
                             message: "Sequence draws one flow at a time. Its list fills from whatever this project has: the paths an Architecture or Data flow drawing names, or the flows the last findings hunt read. Any one is enough. Or name a flow to draw it now:")
                nameFlowForm
            }
            .frame(maxWidth: 560)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
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

    /// An architecture diagram in a repo with a commit but no `origin` remote. Archify checks architecture's
    /// evidence against a GitHub `origin` (`^https://github.com/owner/repo`), so it cannot validate without one. Ask for the URL
    /// — nothing is pushed — then add the remote and draw. This is the renderer's requirement, not the app's.
    @ViewBuilder private var needsRemoteContent: some View {
        NoticeBanner(tone: .waiting, title: "This repository has no GitHub remote",
                     message: "An architecture diagram pins every component to code at a commit, and Archify (the renderer) checks those pins against the repo's GitHub origin. Add the repo's GitHub URL below — nothing is pushed — then the diagram can be drawn. Data flow and sequence draw without one.")
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
        return model.diagramGenerateBlockedReason(kind: selectedKey, agent: agentName)
    }

    private func generate() {
        guard let terminals, let agentName else { return }
        if isSequence {
            guard let flow = currentFlow, let root = repositoryRoot else { return }
            let repo = SequenceFlows.slug(URL(fileURLWithPath: root).lastPathComponent)
            model.generateDiagram(kind: flow.generateKey, drawKind: "sequence", outputName: "\(repo)-sequence-\(flow.slug)",
                                  target: flow.name, agent: agentName, terminals: terminals,
                                  worktreeLocation: worktreeLocation)
            return
        }
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

/// The three kinds the screen offers (ADR 0047), in `ArchDiagrams.kinds` order: the title reads, the token is the argument.
private struct ArchDiagramKind: Identifiable {
    let token: String
    let title: String
    let help: String
    var id: String { token }

    static let all = [
        ArchDiagramKind(token: "architecture", title: "Architecture", help: "The parts of the project and how they connect"),
        ArchDiagramKind(token: "dataflow", title: "Data flow", help: "Where the data comes from, what changes it, and where it is kept"),
        ArchDiagramKind(token: "sequence", title: "Sequence", help: "One flow over time — pick a flow on the left"),
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

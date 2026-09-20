import DeskCore
import SwiftUI

/// One project on screen: the rail and its content. It was `ProjectWindow`, which OWNED the project — its
/// model, its sessions, its Auto loop — so a project existed only while a window was open on it. The strip
/// keeps every project alive (ADR 0050), so this is now only the view of one: everything that must go on
/// happening while you are looking elsewhere lives in `ProjectContext` and `ProjectHooks`.
struct ProjectHost: View {
    let context: ProjectContext
    /// Icons only, asked for by hand (⇧⌘S). Nothing overrides it.
    @AppStorage(PreferenceKey.sidebarRail) private var railMode = false
    @AppStorage(PreferenceKey.worktreeLocation) private var worktreeLocation = AgentDefaults.worktreeLocation

    private var model: ProjectWindowModel { context.model }
    private var terminals: ShellTerminalRegistry { context.terminals }

    var body: some View {
        GeometryReader { proxy in
            host(size: proxy.size)
                // Measured once and handed down, because a sheet cannot measure the window it covers.
                .environment(\.deskWindowSize, proxy.size)
        }
    }

    private func host(size: CGSize) -> some View {
        // The developer's choice, at every width. It used to be `railMode || width < railBreakpoint`, so on
        // any window under 1100 pt the rail was forced and ⇧⌘S silently did nothing — a toggle that answers
        // to nothing is broken, whatever its reasoning (2026-09-20, reported against a 950 pt window). A
        // narrow window with labels is survivable now: the board falls back to columns you scroll.
        let isRail = railMode
        // Our own column, not a `NavigationSplitView`. The split view's sidebar toggle collapses the rail out
        // of the window — a state this app does not have, since the rail is either labels or icons (⇧⌘S) —
        // and `toolbar(removing: .sidebarToggle)` does not remove it on macOS 26, so the window carried two
        // toggles side by side (2026-09-20, on screen). Nothing else here was the split view's: the rail
        // draws its own ground, border and width.
        return HStack(spacing: 0) {
            Sidebar(context: context, isRail: isRail)
                .frame(width: isRail ? DeskMetric.sidebarRailWidth : DeskMetric.sidebarWidth)
            ContentRouter(model: model)
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        }
        .animation(.easeOut(duration: 0.14), value: isRail)
        .toolbar { railToggleItem }
        .toolbar { ProjectToolbar(model: model, terminals: terminals) }
        .navigationTitle(model.snapshot?.project.name ?? context.ref.displayName)
        .navigationSubtitle(subtitle)
        .sheet(item: Bindable(model).sheet) { kind in
            SheetHost(model: model, kind: kind)
        }
        .modifier(DeskLinkRouting(model: model))
        .environment(\.terminals, terminals)
        .focusedSceneValue(\.projectModel, model)
        .onChange(of: model.windowCommand) { _, request in
            guard let request else { return }
            model.windowCommand = nil
            switch request.command {
            case .run:
                if let target = model.runTarget {
                    model.requestProjectRun(target: target, terminals: terminals, worktreeLocation: worktreeLocation)
                }
            case .stop:
                let target = model.runTarget?.folder.standardizedFileURL
                let runs = model.projectRuns
                // The run in the folder ⌘R would target, else whatever is live.
                let id = runs.sessionIDs.first { runs.isLive(sessionID: $0) && runs.sessionFolders[$0].map { URL(fileURLWithPath: $0).standardizedFileURL } == target }
                    ?? runs.liveSessionID
                if let id { model.stopProjectRun(sessionID: id, terminals: terminals) }
            }
        }
        .confirmationDialog(model.pendingRunReplacement.map { "\($0.configurationName) is running on \($0.liveBranch)" } ?? "",
                            isPresented: Binding(get: { model.pendingRunReplacement != nil },
                                                 set: { if !$0 { model.pendingRunReplacement = nil } }),
                            titleVisibility: .visible) {
            Button("Stop it and run \(model.pendingRunReplacement?.branch ?? "here")") {
                model.confirmRunReplacement(terminals: terminals, worktreeLocation: worktreeLocation)
            }
            Button("Cancel", role: .cancel) { model.pendingRunReplacement = nil }
        } message: {
            Text("Both would use the same port, so only one run of a configuration goes at a time.")
        }
    }

    /// macOS 26 gives every toolbar item a pale glass capsule of its own; the controls carry Dev Desk's own
    /// chrome, so the system's is turned off here as it is on the right-hand items.
    @ToolbarContentBuilder private var railToggleItem: some ToolbarContent {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            ToolbarItem(placement: .navigation) { RailToggle(isRail: $railMode) }
                .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: .navigation) { RailToggle(isRail: $railMode) }
        }
        #else
        ToolbarItem(placement: .navigation) { RailToggle(isRail: $railMode) }
        #endif
    }

    private var subtitle: String {
        guard let project = model.snapshot?.project, !project.branch.isEmpty else { return "" }
        return "\(project.displayPath) · \(project.branch)"
    }
}

/// A background door that files or edits an issue changes the tracker this project is reading, and nothing on
/// screen knows that. Rather than wait out the refresh interval, reload as soon as one finishes here: filing
/// is supposed to put a card on the board, and a board that only catches up a minute later reads as filing
/// having done nothing.
///
/// It also finishes a promotion (ADR 0027): when a run filing a `docs/backlog/` entry reports its issue, the
/// entry is moved to `filed/` so GitHub owns it from then on. A run that reports no number leaves the file
/// where it is — guessing which issue it made is how an entry gets marked as the wrong one.
struct FiledWorkHook: View {
    let model: ProjectWindowModel
    @Environment(JobRegistry.self) private var jobs: JobRegistry?
    @State private var settled: Set<String> = []

    /// Finished runs in THIS project, by id. A change means one just ended — and jobs from another project
    /// never move it.
    private var finishedHere: [BackgroundJob] {
        guard let jobs, case .local(let path) = model.ref else { return [] }
        return jobs.jobs.filter { $0.directory == path && !$0.state.isLive }
    }

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onChange(of: finishedHere.map(\.id)) { _, _ in settle() }
    }

    private func settle() {
        let fresh = finishedHere.filter { !settled.contains($0.id) }
        guard !fresh.isEmpty else { return }
        settled.formUnion(fresh.map(\.id))
        Task {
            for job in fresh {
                guard job.door == "create-issue", let subject = job.subject, subject.hasPrefix(DeskTask.localPrefix),
                      case .ended(let text, false) = job.state,
                      let number = LocalBacklog.issueNumber(inRunResult: text, slug: model.snapshot?.slug) else { continue }
                await model.markLocalItemFiled(entry: String(subject.dropFirst(DeskTask.localPrefix.count)), issue: number)
            }
            await model.sync()
        }
    }
}

/// Routes `desk://` links in-app and lets only web and mail links leave it; any other scheme a repository's text carries is discarded unopened.
struct DeskLinkRouting: ViewModifier {
    let model: ProjectWindowModel

    static func opensExternally(_ url: URL) -> Bool {
        ["http", "https", "mailto"].contains(url.scheme?.lowercased() ?? "")
    }

    func body(content: Content) -> some View {
        content.environment(\.openURL, OpenURLAction { url in
            if let link = DeskLink(url: url) {
                model.handle(link)
                return .handled
            }
            return Self.opensExternally(url) ? .systemAction : .discarded
        })
    }
}

extension ProjectRef {
    var displayName: String {
        switch self {
        case .sample(let project): return project.title
        case .local(let path): return URL(fileURLWithPath: path).lastPathComponent
        }
    }
}

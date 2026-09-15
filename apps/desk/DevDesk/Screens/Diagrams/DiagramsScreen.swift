import DeskCore
import SwiftUI

/// The project, drawn: the diagrams `dev:arch` wrote down the left, the one you chose filling the rest. Asking
/// about the project in words is a chat session now — Sessions → New chat — so this screen no longer carries a
/// conversation beside the drawings. The app lists and shows what the door drew; it never draws one itself.
struct InsightsScreen: View {
    @Bindable var model: ProjectWindowModel
    @AppStorage(PreferenceKey.defaultConnection) private var defaultConnection = AgentDefaults.connection
    @State private var diagrams: [ArchDiagram] = []
    @State private var selectedDiagramID: String?
    @State private var archType = "architecture"
    @State private var archTarget = ""
    /// Whether the type/target chooser is showing while diagrams already exist. The empty state shows it
    /// always; a populated pane shows it only when "New diagram" was pressed, so adding one more is possible.
    @State private var isAddingDiagram = false

    private var repositoryRoot: String? { model.snapshot?.repositoryRoot }
    private var selectedDiagram: ArchDiagram? {
        diagrams.first { $0.id == selectedDiagramID } ?? diagrams.first
    }

    var body: some View {
        HStack(spacing: 0) {
            diagramRail
            VStack(spacing: 0) {
                header
                architecture
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(DeskColor.canvas)
        // The folder is read when the project is, not on every redraw: a pane that lists files must not list
        // them in body. A reload counts as the project being read again, and a finished dev:arch run causes one,
        // so what it drew is listed here without anyone watching the folder for it.
        .task(id: model.lastLoadedAt) {
            diagrams = repositoryRoot.map(ArchDiagrams.list) ?? []
            if selectedDiagramID == nil || !diagrams.contains(where: { $0.id == selectedDiagramID }) {
                selectedDiagramID = diagrams.first?.id
            }
        }
    }

    /// The diagrams `dev:arch` wrote, by name.
    private var diagramRail: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Diagrams")
                .font(DeskFont.body.weight(.semibold))
                .foregroundStyle(DeskColor.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 12))
                .overlay(alignment: .bottom) { Rectangle().fill(DeskColor.divider).frame(height: 1) }

            if diagrams.isEmpty {
                Text("No diagrams yet")
                    .font(DeskFont.secondary)
                    .foregroundStyle(DeskColor.mutedInk)
                    .padding(14)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(diagrams) { diagram in
                            Button { selectedDiagramID = diagram.id } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(diagram.title)
                                        .font(DeskFont.secondary)
                                        .foregroundStyle(DeskColor.ink)
                                        .lineLimit(2)
                                    Text(diagram.url.lastPathComponent)
                                        .font(DeskFont.mono(11))
                                        .foregroundStyle(DeskColor.faintInk)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(EdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 12))
                                .background(selectedDiagram?.id == diagram.id ? DeskColor.tone(.info).fill : Color.clear)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(selectedDiagram?.id == diagram.id ? .isSelected : [])
                        }
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

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "rectangle.3.group")
                .foregroundStyle(DeskColor.accent)
                .frame(width: 28, height: 28)
                .background(DeskColor.tone(.info).fill, in: RoundedRectangle(cornerRadius: DeskMetric.controlRadius))
            VStack(alignment: .leading, spacing: 1) {
                Text("Diagrams").font(DeskFont.section).foregroundStyle(DeskColor.ink)
                Text("Architecture diagrams for this project")
                    .font(DeskFont.secondary)
                    .foregroundStyle(DeskColor.mutedInk)
            }
            Spacer(minLength: 8)
            // A repo holds more than one diagram, so once any exist the header does two things: draw another
            // (the chooser, which the empty state shows on its own), and redraw the one on screen as its own type.
            if !diagrams.isEmpty {
                Button("New diagram") { isAddingDiagram = true }
                    .buttonStyle(DeskButtonStyle(kind: .secondary, size: .small))
                    .disabled(runBlockedReason != nil || isAddingDiagram)
                    .help(runBlockedReason ?? "Choose a type and target, then run dev:arch to add another diagram")
                // Regenerates the SELECTED diagram as its own type and target — not always a whole-project
                // architecture run. A diagram with no readable sidecar falls back to a whole-project architecture.
                Button("Regenerate") { regenerateSelected() }
                    .buttonStyle(DeskButtonStyle(kind: .secondary, size: .small))
                    .disabled(runBlockedReason != nil || selectedDiagram == nil)
                    .help(runBlockedReason ?? regenerateHelp)
            }
        }
        .padding(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
        .background(DeskColor.surface)
        .overlay(alignment: .bottom) { Rectangle().fill(DeskColor.divider).frame(height: 1) }
    }

    @ViewBuilder private var architecture: some View {
        if isAddingDiagram, !diagrams.isEmpty {
            // Adding one more to a repo that already has some: the same chooser the empty state uses, over the
            // diagram list rather than replacing it, with a Cancel back to the drawing on screen.
            archStarter
        } else if let diagram = selectedDiagram {
            WebView(file: diagram.url)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            archStarter
        }
    }

    /// Why no run can start here — a sample, or a door already going — or nil when one can.
    private var runBlockedReason: String? { model.runBlockedReason(agent: defaultConnection) }

    /// The chooser: nothing drawn yet, or "New diagram" on a repo that already has some. The answers here are
    /// only `dev:arch`'s own arguments — the app still draws nothing itself.
    private var archStarter: some View {
        let blocked = runBlockedReason
        return VStack {
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 12) {
                if isAddingDiagram {
                    NoticeBanner(tone: .neutral, title: "New diagram",
                                 message: "Pick a type and what to draw, then run dev:arch. It writes another standalone HTML file to docs/arch/ beside the ones already here.")
                } else {
                    NoticeBanner(tone: .neutral, title: "No diagrams yet",
                                 message: "dev:arch draws this project and writes each diagram to docs/arch/ as a standalone HTML file. Run it, and they appear here.")
                }
                if let blocked {
                    NoticeBanner(tone: .neutral, title: "Nothing to run here", message: blocked, style: .compact)
                }
                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel("Diagram")
                    FlowLayout(spacing: 6) {
                        ForEach(ArchDiagramType.all) { type in
                            FocusChip(title: type.title, isOn: archType == type.token) { archType = type.token }
                        }
                    }
                    SectionLabel("What to draw").padding(.top, 6)
                    TextField("What to draw — e.g. the auth flow, or web/app/lib. Leave empty to draw the whole project.",
                              text: $archTarget)
                        .textFieldStyle(.plain)
                        .font(DeskFont.body)
                        .padding(.horizontal, 10)
                        .controlChrome(height: 28)
                }
                HStack(spacing: 8) {
                    Spacer(minLength: 0)
                    // Cancel only exists while adding to an existing set — the empty state has nothing to go back to.
                    if isAddingDiagram {
                        Button("Cancel") { isAddingDiagram = false }
                            .buttonStyle(DeskButtonStyle(kind: .secondary, size: .small))
                    }
                    Button(isAddingDiagram ? "Draw diagram" : "Start dev:arch") { startArch() }
                        .buttonStyle(DeskButtonStyle(kind: .primary, size: .small))
                        .disabled(blocked != nil)
                }
            }
            .frame(maxWidth: 560)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    /// The `help` on Regenerate, naming the type it will redraw the selected diagram as.
    private var regenerateHelp: String {
        guard let diagram = selectedDiagram else { return "Redraws the selected diagram" }
        let type = ArchDiagramType.all.first { $0.token == diagram.kind }?.title
            ?? diagram.kind?.capitalized ?? "Architecture"
        return "Runs dev:arch again to redraw “\(diagram.title)” as a \(type) diagram"
    }

    /// Draw what the chooser holds: the picked type, with the target if one was typed. Used for the first
    /// diagram and for "New diagram"; closing the chooser afterwards returns a populated pane to its drawing.
    private func startArch() {
        run(type: archType, target: archTarget.trimmingCharacters(in: .whitespacesAndNewlines))
        isAddingDiagram = false
    }

    /// Redraw the SELECTED diagram as its own recorded type — not a fresh whole-project architecture run. A
    /// diagram whose sidecar could not be read (no `kind`) falls back to a whole-project architecture diagram.
    private func regenerateSelected() {
        guard let diagram = selectedDiagram else { return }
        run(type: diagram.kind ?? "architecture", target: "")
    }

    /// Start one `dev:arch` run. The door reads what to draw first and a bare type token after it, so a target
    /// leads and the type follows; an empty target means the whole project.
    private func run(type: String, target: String) {
        var arguments: [String] = []
        if !target.isEmpty { arguments.append(target) }
        arguments.append(type)
        model.prepareRun(door: "arch", title: "Architecture diagram", agent: defaultConnection, arguments: arguments,
                         folderNote: "dev:arch reads the whole project, so it runs at the project root.")
    }
}

/// The diagrams `dev:arch` knows how to draw, in the skill's own order: the title reads, the token is the argument.
private struct ArchDiagramType: Identifiable {
    let token: String
    let title: String
    var id: String { token }

    static let all = [
        ArchDiagramType(token: "architecture", title: "Architecture"),
        ArchDiagramType(token: "workflow", title: "Workflow"),
        ArchDiagramType(token: "dataflow", title: "Data flow"),
        ArchDiagramType(token: "sequence", title: "Sequence"),
        ArchDiagramType(token: "lifecycle", title: "Lifecycle"),
    ]
}

struct InsightsScreen_Previews: PreviewProvider {
    static var previews: some View {
        PreviewHost().frame(width: 1180, height: 800)
    }

    private struct PreviewHost: View {
        @State private var model = ProjectWindowModel(ref: .sample(.studyHub), source: SampleDataSource(project: .studyHub))

        var body: some View {
            InsightsScreen(model: model)
                .task {
                    await model.load()
                    model.go(.insights)
                }
        }
    }
}

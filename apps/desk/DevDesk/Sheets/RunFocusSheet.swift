import DeskCore
import SwiftUI

/// What a run should look at, asked before it starts. Every choice here is an argument the door already
/// understands, so narrowing the run in the app and narrowing it on the command line mean the same thing.
struct RunFocusSheet: View {
    @Bindable var model: ProjectWindowModel
    let door: String
    @AppStorage(PreferenceKey.defaultConnection) private var defaultConnection = AgentDefaults.connection
    @AppStorage(PreferenceKey.backgroundConnection) private var storedBackground = ""
    @State private var kinds: Set<IdeationKind> = []
    @State private var scope: FindingsScope = .both
    @State private var flow = ""
    @State private var inBackground = false
    @State private var permission: RunPermission = .writeInRepo
    @State private var stops = RunStops()
    @State private var loadedStops = false
    @AppStorage(PreferenceKey.runMaxAgents) private var runMaxAgents = RunStops.defaultMaxAgents
    @Environment(JobRegistry.self) private var jobs: JobRegistry?

    private var isIdeation: Bool { door == "ideation" }
    private var isRoadmap: Bool { door == "roadmap" }
    private var isFindingsRun: Bool { !isIdeation && !isRoadmap }

    /// Whether starting this run now would collide with one already going in the background. Findings answers
    /// it by scope: a defects run and an architecture run write different halves of the report and belong
    /// side by side, while the same half twice — or anything beside `both`, which writes the whole report —
    /// would overwrite itself. Every other door is one at a time, as it was.
    private var backgroundConflict: Bool {
        guard let jobs, case .local(let path) = model.ref else { return false }
        return isFindingsRun ? jobs.hasLiveFindingsRun(scope: scope, in: path) : jobs.hasLiveJob(door: door, in: path)
    }

    /// In the background the run needs a headless form, so it uses the Background runs setting; in a terminal, any
    /// agent the default names.
    private var agent: String {
        inBackground ? BackgroundConnection.resolve(stored: storedBackground, defaultConnection: defaultConnection)
            : defaultConnection
    }

    var body: some View {
        let blocked = model.runBlockedReason(agent: agent)
        SheetChrome(title: title,
                    confirmTitle: "Start run", confirmDisabled: blocked != nil,
                    onCancel: model.dismissSheet, onConfirm: start) {
            VStack(alignment: .leading, spacing: 12) {
                if let blocked {
                    NoticeBanner(tone: .neutral, title: "Nothing to run here", message: blocked, style: .compact)
                }
                if isRoadmap {
                    EmptyView()
                } else if isIdeation {
                    kindPicker
                } else {
                    scopePicker
                }
                if !isRoadmap { stopsPicker }
                backgroundPicker
                Text(footnote)
                    .font(.system(size: 11))
                    .foregroundStyle(DeskColor.faintInk)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear {
            guard !loadedStops else { return }
            loadedStops = true
            stops = RunStops(stored: UserDefaults.standard.string(forKey: PreferenceKey.runStops(model.ref, door: door)) ?? "",
                             maxAgents: runMaxAgents)
        }
    }

    /// What the run does at each point it would stop and ask (ADR 0043). Chosen here because a background
    /// run has nobody to ask, and a terminal run asked three times is a run started three times.
    private var stopsPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("When the run reaches…").padding(.top, 6)
            stopRow("Planning agents", choices: [.decide, .alert], selection: $stops.plan)
            stopRow("Walkthrough", choices: StopChoice.allCases, selection: $stops.walkthrough)
            stopRow("Filing", choices: StopChoice.allCases, selection: $stops.filing)
            Text("Limit: \(runMaxAgents) agents — a plan that needs more starts nothing and says why. Change it in Settings → Execution.")
                .font(.system(size: 11))
                .foregroundStyle(DeskColor.faintInk)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func stopRow(_ title: String, choices: [StopChoice], selection: Binding<StopChoice>) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(DeskFont.body)
                .foregroundStyle(DeskColor.ink)
                .frame(width: 130, alignment: .leading)
            FlowLayout(spacing: 6) {
                ForEach(choices, id: \.self) { choice in
                    FocusChip(title: choice.title, isOn: selection.wrappedValue == choice) { selection.wrappedValue = choice }
                }
            }
        }
    }

    private var kindPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Kinds")
            FlowLayout(spacing: 6) {
                ForEach(IdeationKind.allCases, id: \.self) { kind in
                    FocusChip(title: kind.title, isOn: kinds.contains(kind)) {
                        if kinds.contains(kind) { kinds.remove(kind) } else { kinds.insert(kind) }
                    }
                }
            }
        }
    }

    private var scopePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Scope")
            FlowLayout(spacing: 6) {
                ForEach(FindingsScope.allCases, id: \.self) { option in
                    FocusChip(title: option.title, isOn: scope == option) { scope = option }
                }
            }
            SectionLabel("One flow only").padding(.top, 6)
            TextField("A flow name, such as checkout — leave empty for every flow it can find", text: $flow)
                .textFieldStyle(.plain)
                .font(DeskFont.body)
                .padding(.horizontal, 10)
                .controlChrome(height: 28)
        }
    }

    /// A run that needs nobody while it works does not need a terminal either. It cannot prompt once it is
    /// headless, so what it may do without asking is chosen here, before it starts (ADR 0025).
    @ViewBuilder private var backgroundPicker: some View {
        if jobs != nil {
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel("Where it runs").padding(.top, 6)
                FlowLayout(spacing: 6) {
                    FocusChip(title: "In a terminal", isOn: !inBackground) { inBackground = false }
                    FocusChip(title: "In the background", isOn: inBackground) { inBackground = true }
                }
                if inBackground, backgroundConflict {
                    NoticeBanner(tone: .neutral, title: "One at a time",
                                 message: conflictMessage,
                                 style: .compact)
                }
                if inBackground {
                    SectionLabel("What it may do without asking").padding(.top, 6)
                    FlowLayout(spacing: 6) {
                        // Read only is not offered here: both doors behind this sheet write a report, and a
                        // run that may not write stalls at its first line of it.
                        ForEach(RunPermission.allCases.filter { $0 != .readOnly }, id: \.self) { option in
                            FocusChip(title: option.title, isOn: permission == option) { permission = option }
                        }
                    }
                    Text(permission.detail)
                        .font(.system(size: 11))
                        .foregroundStyle(DeskColor.faintInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var title: String {
        if isRoadmap { return "Run the roadmap door?" }
        return isIdeation ? "What should this ideation run look for?" : "What should this findings run look at?"
    }

    private var footnote: String {
        if isRoadmap {
            return "The door reads this repository's own recorded gaps, PROJECT_MAP's orphans and pending work, and any findings or ideation reports — then proposes milestones with epic parents underneath. It never invents work, and it asks before filing anything."
        }
        return isIdeation
            ? "Nothing selected means all three kinds, which is the door's own default."
            : "The door discovers the flows it can see and verifies every finding against the code, from scratch."
    }

    /// Why the run cannot start, in the terms it was chosen in. A findings run names the half that is taken,
    /// because "a findings run is already going" is the wrong answer when the other half is free to start.
    private var conflictMessage: String {
        guard isFindingsRun else {
            return "A background \(door) run is already going. Two would write the same report over each other."
        }
        return "A background findings run is already writing \(scope == .both ? "this report" : "this half of the report"). "
            + "Two would write it over each other — the other half can still be started on its own."
    }

    private func start() {
        var arguments: [String] = []
        if isIdeation {
            arguments = IdeationKind.allCases.filter(kinds.contains).map(\.argument)
        } else {
            if let argument = scope.argument { arguments.append(argument) }
            let name = flow.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty { arguments.append(name) }
        }
        if !isRoadmap {
            let chosen = RunStops(plan: stops.plan, walkthrough: stops.walkthrough, filing: stops.filing, maxAgents: runMaxAgents)
            arguments += chosen.arguments
            UserDefaults.standard.set(chosen.stored, forKey: PreferenceKey.runStops(model.ref, door: door))
        }
        // The scope names the run and nothing else: the door stays "findings", so the same SKILL is read.
        let title = isRoadmap ? "Roadmap" : (isIdeation ? "Ideation" : scope.runTitle)
        if inBackground, let jobs, case .local(let path) = model.ref, !backgroundConflict {
            jobs.start(door: door, title: title, agent: agent, arguments: arguments,
                       permission: permission, directory: path, mode: RunModeChoice.current(for: model.ref),
                       scope: isFindingsRun ? scope : nil)
            model.go(.terminals)
        } else if isFindingsRun, model.isFindingsRunLive(scope: scope) {
            // A terminal is already writing this half. Show that run rather than open a second shell over it:
            // `prepareRun` refuses a second run under the same id, but `both` beside a live `defects` is a
            // different id and would otherwise start.
            model.go(.terminals)
        } else {
            model.prepareRun(door: door, title: title, agent: defaultConnection, arguments: arguments,
                             id: isFindingsRun ? DoorRuns.id(door: door, scope: scope) : nil)
        }
        model.dismissSheet()
    }
}

/// `dev:findings`'s own arguments: both halves by default, or one of them. The cases are DeskCore's
/// `FindingsRunScope`, because which of them may run beside which is a rule the job registry has to hold too;
/// the sheet adds only how each choice reads and what it puts on the command line.
typealias FindingsScope = FindingsRunScope

extension FindingsScope {
    var title: String {
        switch self {
        case .both: return "Defects and architecture"
        case .defects: return "Defects only"
        case .architecture: return "Architecture only"
        }
    }

    var argument: String? {
        switch self {
        case .both: return nil
        case .defects: return "--bugs"
        case .architecture: return "--arch"
        }
    }
}

/// Also used by Terminals to pick how many are up: one chip style for "one of these, on or off".
struct FocusChip: View {
    let title: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(DeskFont.secondary)
                .foregroundStyle(isOn ? Color.white : DeskColor.ink)
                .padding(.vertical, 5)
                .padding(.horizontal, 11)
                .background(isOn ? DeskColor.accent : DeskColor.surface, in: RoundedRectangle(cornerRadius: DeskMetric.pillRadius))
                .overlay(RoundedRectangle(cornerRadius: DeskMetric.pillRadius).strokeBorder(isOn ? DeskColor.accent : DeskColor.controlBorder))
                .fixedSize()
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

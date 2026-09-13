import DeskCore
import SwiftUI

/// What a run should look at, asked before it starts. Every choice here is an argument the door already
/// understands, so narrowing the run in the app and narrowing it on the command line mean the same thing.
struct RunFocusSheet: View {
    @Bindable var model: ProjectWindowModel
    let door: String
    @AppStorage(PreferenceKey.defaultConnection) private var defaultConnection = AgentDefaults.connection
    @State private var kinds: Set<IdeationKind> = []
    @State private var scope: SurveyScope = .both
    @State private var flow = ""
    @State private var inBackground = false
    @State private var permission: RunPermission = .writeInRepo
    @Environment(JobRegistry.self) private var jobs: JobRegistry?

    private var isIdeation: Bool { door == "ideation" }
    private var isRoadmap: Bool { door == "roadmap" }

    var body: some View {
        let blocked = model.runBlockedReason(agent: defaultConnection)
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
                backgroundPicker
                Text(footnote)
                    .font(.system(size: 11))
                    .foregroundStyle(DeskColor.faintInk)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
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
                ForEach(SurveyScope.allCases, id: \.self) { option in
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
                if inBackground, case .local(let path) = model.ref, jobs?.hasLiveJob(door: door, in: path) == true {
                    NoticeBanner(tone: .neutral, title: "One at a time",
                                 message: "A background \(door) run is already going. Two would write the same report over each other.",
                                 style: .compact)
                }
                if inBackground {
                    SectionLabel("What it may do without asking").padding(.top, 6)
                    FlowLayout(spacing: 6) {
                        ForEach(RunPermission.allCases, id: \.self) { option in
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
        return isIdeation ? "What should this ideation run look for?" : "What should this survey look at?"
    }

    private var footnote: String {
        if isRoadmap {
            return "The door reads this repository's own recorded gaps, PROJECT_MAP's orphans and pending work, and any survey or ideation reports — then proposes milestones with epic parents underneath. It never invents work, and it asks before filing anything."
        }
        return isIdeation
            ? "Nothing selected means all three kinds, which is the door's own default. The run still asks before it files anything."
            : "The door discovers the flows it can see, verifies every finding against the code, and asks before filing."
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
        let title = isRoadmap ? "Roadmap" : (isIdeation ? "Ideation" : "Survey")
        if inBackground, let jobs, case .local(let path) = model.ref, !jobs.hasLiveJob(door: door, in: path) {
            jobs.start(door: door, title: title, agent: defaultConnection, arguments: arguments,
                       permission: permission, directory: path)
            model.go(.terminals)
        } else {
            model.prepareRun(door: door, title: title, agent: defaultConnection, arguments: arguments)
        }
        model.dismissSheet()
    }
}

/// `dev:survey`'s own arguments: both halves by default, or one of them.
enum SurveyScope: String, CaseIterable, Hashable {
    case both, defects, architecture

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

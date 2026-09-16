import AppKit
import DeskCore
import SwiftUI

/// The slot meter the footer prints: `3 of 5 running · 2 elsewhere`. `elsewhere` is counted and never
/// governed — the app can neither see nor stop a handed-off run's tokens (ADR 0036 decision 5).
struct StartSlots: Hashable {
    let running: Int
    let limit: Int
    var elsewhere = 0

    var free: Int { max(limit - running, 0) }

    var line: String {
        let meter = "\(running) of \(limit) running"
        return elsewhere > 0 ? "\(meter) · \(elsewhere) elsewhere" : meter
    }
}

/// How gates are answered once a run is under way. Both policies block: every *Run it here* row is a
/// protocol session, so there is no third meaning hiding behind identical chrome (ADR 0036 decision 2).
enum StartPermissionPolicy: String, CaseIterable, Hashable {
    case atGates, everyTool

    var title: String {
        switch self {
        case .atGates: return "Ask at gates"
        case .everyTool: return "Ask every tool"
        }
    }
}

/// The sheet a start opens: the `TaskLaunch` on the left, who may carry it on the right, and **nothing runs
/// until the primary button** (ADR 0036 decision 1). It is a pure view over values — it detects nothing and
/// spawns nothing, and the only state it owns is which row is ticked.
struct StartSheet: View {
    let launch: TaskLaunch
    let choices: RunnerChoices
    /// The prompt as `TaskLaunch.prompt(home:)` already resolved it; the sheet never composes one itself.
    let prompt: String
    let slots: StartSlots
    /// Drives the `first start` chip only. The compact confirm for a second start is a different surface (§10.3
    /// answer 3), so this sheet says which one it is rather than deciding when to appear.
    var isFirstStart = true
    let onCancel: () -> Void
    let onStart: (RunnerOption, StartPermissionPolicy) -> Void

    @State private var selectedRunnerID: String?
    @State private var policy: StartPermissionPolicy = .atGates

    init(launch: TaskLaunch, choices: RunnerChoices, prompt: String, slots: StartSlots, isFirstStart: Bool = true,
         onCancel: @escaping () -> Void, onStart: @escaping (RunnerOption, StartPermissionPolicy) -> Void) {
        self.launch = launch
        self.choices = choices
        self.prompt = prompt
        self.slots = slots
        self.isFirstStart = isFirstStart
        self.onCancel = onCancel
        self.onStart = onStart
        _selectedRunnerID = State(initialValue: choices.runnable.first?.id)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            HStack(alignment: .top, spacing: 16) {
                payload
                side
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            footer
        }
        .deskDialogFrame()
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(DeskColor.ink)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Text("Nothing runs until you press the button.")
                        .font(DeskFont.secondary)
                        .foregroundStyle(DeskColor.mutedInk)
                    if isFirstStart {
                        StatusPill(badge: StatusBadge(.info, "first start"))
                    }
                }
            }
            Spacer(minLength: 8)
            DialogGlyph(symbol: "xmark", label: "Close", action: onCancel)
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 14)
        .background(DeskColor.headerFill)
    }

    /// `Start #212 — <title>` when a card owns the launch; a door run has no number to print, so it says the door.
    private var title: String {
        guard let task = launch.task else { return "Start \(launch.door) — \(launch.title)" }
        return "Start #\(task) — \(launch.title)"
    }

    // MARK: - Payload

    private var payload: some View {
        VStack(alignment: .leading, spacing: 9) {
            KeyValueTable(rows: payloadRows, keyWidth: 96)
            promptBox
            HStack(spacing: 7) {
                Button("Copy task file", action: copyTaskFile)
                    .buttonStyle(DeskButtonStyle(kind: .secondary, size: .mini))
                    .help("Copies the launch payload as JSON, the form every runner reads")
                Button("Reveal", action: revealFolder)
                    .buttonStyle(DeskButtonStyle(kind: .secondary, size: .mini))
                    .help("Shows the worktree location in Finder")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Only what the launch actually carries. A row with no value is left out rather than printed with a dash:
    /// `TaskLaunch` pins no branch and no gate list, and a placeholder there would read as a decision taken.
    private var payloadRows: [KeyValue] {
        var rows = [KeyValue("Door", ([launch.door] + launch.arguments).joined(separator: " "), monospaced: true)]
        if !launch.worktreeLocation.isEmpty {
            rows.append(KeyValue("Folder", launch.worktreeLocation, monospaced: true))
        }
        if let base = launch.base {
            rows.append(KeyValue("Base", base.display, monospaced: true))
        }
        if launch.mode != .standard {
            rows.append(KeyValue("Mode", launch.mode.title))
        }
        rows.append(KeyValue("Task file", taskFilePath, monospaced: true))
        return rows
    }

    /// The path ADR 0036 decision 1 fixes. It is relative because the sheet is handed a launch, not a project root.
    private var taskFilePath: String { ".devdesk/launch/\(launch.id).json" }

    private var promptBox: some View {
        ScrollView {
            Text(prompt)
                .font(DeskFont.mono(11.5))
                .foregroundStyle(DeskColor.ink)
                .textSelection(.enabled)
                .lineSpacing(3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(11)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(DeskColor.canvas, in: RoundedRectangle(cornerRadius: DeskMetric.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: DeskMetric.cardRadius).strokeBorder(DeskColor.border))
    }

    private func copyTaskFile() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(launch), let json = String(data: data, encoding: .utf8) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(json, forType: .string)
    }

    /// The worktree location, not the task file: the launch names where the work goes, and the file it would be
    /// written to is relative to a project root this view is deliberately not given.
    private func revealFolder() {
        let path = (launch.worktreeLocation as NSString).expandingTildeInPath
        guard !path.isEmpty else { return }
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
    }

    // MARK: - The two lists and the policy

    private var side: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                SectionLabel("Run it here")
                Text("· acp only")
                    .font(DeskFont.small)
                    .foregroundStyle(DeskColor.faintInk)
            }
            hereList
            SectionLabel("Or hand it to")
                .padding(.top, 4)
            ForEach(choices.handoff) { option in
                runnerRow(option)
            }
            SectionLabel("Permissions")
                .padding(.top, 4)
            ForEach(StartPermissionPolicy.allCases, id: \.self) { choice in
                optionRow(title: choice.title, detail: nil, isSelected: policy == choice, isAvailable: true) {
                    policy = choice
                }
            }
        }
        .frame(width: 252, alignment: .leading)
    }

    /// The honest-empty state ADR 0036 decision 2 turns on: with no adapter found the section says why and the
    /// hand-offs are the answer. Nothing is demoted into a weaker runner to fill it.
    @ViewBuilder private var hereList: some View {
        if choices.here.isEmpty {
            NoticeBanner(tone: .waiting, title: "",
                         message: choices.hereEmptyReason ?? "No ACP adapter was found.", style: .compact)
        } else {
            ForEach(choices.here) { option in
                runnerRow(option)
            }
        }
    }

    private func runnerRow(_ option: RunnerOption) -> some View {
        optionRow(title: option.name, detail: option.detail, isSelected: selectedRunnerID == option.id,
                  isAvailable: option.isAvailable) {
            selectedRunnerID = option.id
        }
    }

    /// One radio row. An unavailable row is still drawn — its `detail` is the reason, and absence is information.
    private func optionRow(title: String, detail: String?, isSelected: Bool, isAvailable: Bool,
                           select: @escaping () -> Void) -> some View {
        Button(action: select) {
            HStack(spacing: 8) {
                Circle()
                    .strokeBorder(isSelected ? DeskColor.accent : DeskColor.controlBorder, lineWidth: isSelected ? 4 : 1)
                    .frame(width: 13, height: 13)
                Text(title)
                    .font(DeskFont.secondary)
                    .foregroundStyle(DeskColor.ink)
                Spacer(minLength: 6)
                if let detail {
                    Text(detail)
                        .font(DeskFont.small)
                        .foregroundStyle(DeskColor.faintInk)
                        .lineLimit(1)
                }
            }
            .padding(.vertical, 7)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? DeskColor.tone(.info).fill : DeskColor.surface,
                        in: RoundedRectangle(cornerRadius: DeskMetric.controlRadius))
            .overlay(RoundedRectangle(cornerRadius: DeskMetric.controlRadius)
                .strokeBorder(isSelected ? DeskColor.accent : DeskColor.border))
            .contentShape(RoundedRectangle(cornerRadius: DeskMetric.controlRadius))
        }
        .buttonStyle(.plain)
        .disabled(!isAvailable)
        .opacity(isAvailable ? 1 : 0.45)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 10) {
            Text(slots.line)
                .font(DeskFont.small)
                .foregroundStyle(DeskColor.mutedInk)
            Spacer(minLength: 8)
            Button("Cancel", action: onCancel)
                .buttonStyle(DeskButtonStyle(kind: .secondary, size: .regular))
            Button(primaryTitle) {
                if let selected { onStart(selected, policy) }
            }
            .buttonStyle(DeskButtonStyle(kind: .primary, size: .regular))
            .disabled(selected == nil)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 13)
        .background(DeskColor.headerFill)
        .overlay(alignment: .top) { Rectangle().fill(DeskColor.divider).frame(height: 1) }
    }

    private var selected: RunnerOption? {
        choices.runnable.first { $0.id == selectedRunnerID }
    }

    /// The button names the choice, and names what that choice does: a hand-off does not run anything here.
    private var primaryTitle: String {
        guard let selected else { return "Start" }
        return selected.kind == .here ? "Run with \(selected.name)" : "Hand it to \(selected.name)"
    }
}

struct StartSheet_Previews: PreviewProvider {
    static let launch = TaskLaunch(id: "212", task: "212", title: "Resume upload fails over 20 MB",
                                   door: "dev", arguments: ["#212"], agent: .claude,
                                   worktreeLocation: "~/.devdesk/wt",
                                   base: LaunchBase(ref: "origin/main", short: "8c1f2a0"))

    static let prompt = """
        You are working issue #212.
        Read shared/entry.md, then shared/pipeline.md.
        Phase 1 — restate the bug in one line, then reproduce it before touching anything.
        """

    static let handoff = [
        RunnerOption(id: "terminal", name: "Terminal", detail: "--from-file", kind: .handoff),
        RunnerOption(id: "super", name: "super.engineering", kind: .handoff),
        RunnerOption(id: "cursor", name: "Cursor", kind: .handoff),
    ]

    static var previews: some View {
        StartSheet(launch: launch,
                   choices: RunnerChoices(here: [
                       RunnerOption(id: "claude", name: "Claude Code", detail: "acp v1", kind: .here),
                       RunnerOption(id: "codex", name: "Codex", detail: "acp v1", kind: .here),
                       RunnerOption(id: "gemini", name: "Gemini CLI", detail: "not installed", kind: .here,
                                    isAvailable: false),
                   ], handoff: handoff),
                   prompt: prompt, slots: StartSlots(running: 3, limit: 5, elsewhere: 2),
                   onCancel: {}, onStart: { _, _ in })
            .previewDisplayName("Adapters found")

        StartSheet(launch: launch,
                   choices: RunnerChoices(here: [], handoff: handoff,
                                          hereEmptyReason: "No ACP adapter was found. Install one, or hand this to a tool below."),
                   prompt: prompt, slots: StartSlots(running: 0, limit: 5),
                   onCancel: {}, onStart: { _, _ in })
            .previewDisplayName("No adapter · the reason")
    }
}

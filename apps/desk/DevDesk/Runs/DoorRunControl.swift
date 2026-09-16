import DeskCore
import SwiftUI

/// Starts a door — and says the door is running when it is, instead of offering to start it again.
///
/// The second press was already refused (`prepareRun` keeps one live run per door, and `JobRegistry` one
/// background job per door), but the button said "Run roadmap" throughout, so the screen claimed nothing was
/// happening while its own Runs panel showed the run below it.
struct DoorRunControl: View {
    let model: ProjectWindowModel
    let door: String
    let title: String
    var size: DeskButtonStyle.Size = .smallWide
    @Environment(JobRegistry.self) private var jobs: JobRegistry?
    @AppStorage(PreferenceKey.defaultConnection) private var defaultConnection = AgentDefaults.connection

    /// In a terminal or in the background — either way this door is busy **in this project**. The registry is
    /// the app's, so the directory is what keeps one window's run out of another's button.
    ///
    /// Findings is the exception: a defects run and an architecture run write different halves of the report,
    /// so one of them going does not mean the button has nothing left to offer. This button opens the sheet
    /// where that half is chosen, so it only says "Running" when no scope at all could still be started —
    /// a `both` run, which occupies the whole report, or a defects run and an architecture run together.
    private var isRunning: Bool {
        if door == "findings" { return FindingsScope.allCases.allSatisfy(isFindingsRunBlocked) }
        if model.isDoorRunning(door) { return true }
        guard case .local(let path) = model.ref else { return false }
        return jobs?.hasLiveJob(door: door, in: path) ?? false
    }

    /// Only the roadmap door waits on another: nil for every other door.
    private var roadmapBlockedReason: String? {
        guard door == "roadmap" else { return nil }
        return ProjectWindowModel.roadmapBlockedReason(findings: model.snapshot?.findings, findingsInProgress: findingsInProgress)
    }

    private var findingsInProgress: Bool { Self.findingsInProgress(model: model, jobs: jobs) }

    /// A Findings run in this window's terminals, or a background one in this project that is running or waiting on an answer.
    static func findingsInProgress(model: ProjectWindowModel, jobs: JobRegistry?) -> Bool {
        if model.isFindingsRunLive() { return true }
        guard case .local(let path) = model.ref else { return false }
        return jobs?.hasUnfinishedJob(door: "findings", in: path) ?? false
    }

    private func isFindingsRunBlocked(_ scope: FindingsScope) -> Bool {
        if model.isFindingsRunLive(scope: scope) { return true }
        guard case .local(let path) = model.ref else { return false }
        return jobs?.hasLiveFindingsRun(scope: scope, in: path) ?? false
    }

    var body: some View {
        if isRunning {
            Button { model.go(.terminals) } label: {
                HStack(spacing: 6) {
                    StatusDot(tone: .running, pulses: true, size: 6)
                    Text("Running")
                }
            }
            .buttonStyle(DeskButtonStyle(kind: .secondary, size: size))
            .help("This door is already running. Open Runs to watch it or stop it.")
            .accessibilityLabel("\(door) is running. Open Runs.")
        } else if door == "roadmap", model.roadmapWaitingForFindings != nil {
            Button { model.cancelRoadmapAfterFindings() } label: {
                HStack(spacing: 6) {
                    StatusDot(tone: .waiting, pulses: true, size: 6)
                    Text("Waiting for Findings")
                }
            }
            .buttonStyle(DeskButtonStyle(kind: .secondary, size: size))
            .help("Roadmap starts once Findings finishes. Click to stop waiting.")
        } else if door == "roadmap", findingsInProgress, model.runBlockedReason(agent: defaultConnection) == nil {
            Button("Run after Findings") {
                model.runRoadmapAfterFindings { [model, jobs] in Self.findingsInProgress(model: model, jobs: jobs) }
            }
            .buttonStyle(DeskButtonStyle(kind: .primary, size: size))
            .help("Findings is still running. Roadmap builds from its report, so this waits for it and then opens Roadmap's start.")
        } else {
            let blocked = model.runBlockedReason(agent: defaultConnection) ?? roadmapBlockedReason
            Button(title) { model.present(.runFocus(door)) }
                .buttonStyle(DeskButtonStyle(kind: .primary, size: size))
                .disabled(blocked != nil)
                .help(blocked ?? "Start dev:\(door) in \(defaultConnection), in this project's folder")
        }
    }
}

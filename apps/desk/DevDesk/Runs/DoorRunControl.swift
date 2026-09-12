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
    @AppStorage(PreferenceKey.defaultConnection) private var defaultConnection = "Codex"

    /// In a terminal or in the background — either way this door is busy **in this project**. The registry is
    /// the app's, so the directory is what keeps one window's run out of another's button.
    private var isRunning: Bool {
        if model.isDoorRunning(door) { return true }
        guard case .local(let path) = model.ref else { return false }
        return jobs?.hasLiveJob(door: door, in: path) ?? false
    }

    var body: some View {
        if isRunning {
            Button { model.showRuns() } label: {
                HStack(spacing: 6) {
                    StatusDot(tone: .running, pulses: true, size: 6)
                    Text("Running")
                }
            }
            .buttonStyle(DeskButtonStyle(kind: .secondary, size: size))
            .help("This door is already running. Open Runs to watch it or stop it.")
            .accessibilityLabel("\(door) is running. Open Runs.")
        } else {
            let blocked = model.runBlockedReason(agent: defaultConnection)
            Button(title) { model.present(.runFocus(door)) }
                .buttonStyle(DeskButtonStyle(kind: .primary, size: size))
                .disabled(blocked != nil)
                .help(blocked ?? "Start dev:\(door) in \(defaultConnection), in this project's folder")
        }
    }
}

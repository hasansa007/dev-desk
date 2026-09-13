import DeskCore
import SwiftUI

/// Starting a project's survey reading over. Three things accumulate and none of them is owned by the same
/// party: the findings you set aside live in the app, the screen's selection lives in the window, and the
/// reports live in the repository. So each is a line with its own count, and nothing is cleared silently.
struct ResetSurveySheet: View {
    @Bindable var model: ProjectWindowModel
    @State private var options = SurveyResetOptions()
    @State private var runAfterwards = false
    @Environment(JobRegistry.self) private var jobs: JobRegistry?

    private var olderReports: [String] { model.olderSurveyReports }
    private var ignoredCount: Int { model.ignoredFindingsCount }

    /// Any survey at all, of any scope, in a terminal or in the background. Scope buys nothing here: a reset
    /// moves the reports both halves are being written into, so one going at all is enough to refuse.
    private var isAnySurveyRunning: Bool {
        if model.isSurveyRunning() { return true }
        guard case .local(let path) = model.ref else { return false }
        return jobs?.hasLiveJob(door: "survey", in: path) ?? false
    }

    var body: some View {
        SheetChrome(title: "Reset survey", confirmTitle: confirmTitle, confirmDisabled: options.isEmpty,
                    onCancel: model.dismissSheet, onConfirm: reset) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Clears what has built up between runs. The newest report is always kept — it is the current picture of this project.")
                    .font(DeskFont.body)
                    .foregroundStyle(DeskColor.secondaryInk)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)

                line(isOn: $options.ignoredFindings,
                     title: "Bring back ignored findings",
                     detail: ignoredCount == 0
                        ? "Nothing is set aside in this project."
                        : "\(ignoredCount) finding\(ignoredCount == 1 ? "" : "s") set aside here. They live in the app, never in docs/survey/.",
                     enabled: ignoredCount > 0)

                line(isOn: $options.viewState,
                     title: "Reset this screen",
                     detail: "Selected run, category filter and the ignored-findings view go back to how the project opens.",
                     enabled: true)

                line(isOn: $options.olderReports,
                     title: "Move older reports to the Trash",
                     detail: reportsDetail,
                     enabled: !olderReports.isEmpty && model.canRunDoors)

                if options.olderReports, !olderReports.isEmpty {
                    Text(olderReports.joined(separator: "   "))
                        .font(DeskFont.mono(11))
                        .foregroundStyle(DeskColor.faintInk)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.leading, 26)
                }

                Divider()

                Toggle(isOn: $runAfterwards) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Run a new survey afterwards").font(DeskFont.body)
                        Text(model.canRunDoors
                             ? "Opens dev:survey in Terminals. Nothing executes until you start it there."
                             : "A sample project has no folder to survey.")
                            .font(DeskFont.secondary)
                            .foregroundStyle(DeskColor.mutedInk)
                    }
                }
                .disabled(!model.canRunDoors || isAnySurveyRunning)
            }
        }
    }

    private var reportsDetail: String {
        guard model.canRunDoors else { return "A sample project has no reports on disk." }
        switch olderReports.count {
        case 0: return "This project has one report or none, so there is nothing older to move."
        case 1: return "1 older report goes to the Trash; the newest stays. Recoverable from the Finder."
        default: return "\(olderReports.count) older reports go to the Trash; the newest stays. Recoverable from the Finder."
        }
    }

    private var confirmTitle: String {
        options.olderReports && !olderReports.isEmpty ? "Reset and move to Trash" : "Reset"
    }

    private func line(isOn: Binding<Bool>, title: String, detail: String, enabled: Bool) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(DeskFont.body)
                Text(detail)
                    .font(DeskFont.secondary)
                    .foregroundStyle(DeskColor.mutedInk)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .disabled(!enabled)
        .onChange(of: enabled) { _, isEnabled in if !isEnabled { isOn.wrappedValue = false } }
        .onAppear { if !enabled { isOn.wrappedValue = false } }
    }

    private func reset() {
        let options = options
        let runAfterwards = runAfterwards
        model.dismissSheet()
        Task {
            await model.resetSurvey(options)
            // The same door start the screen's own button uses: it asks what to focus on first, and nothing
            // executes until you start it in Terminals.
            if runAfterwards { model.present(.runFocus("survey")) }
        }
    }
}

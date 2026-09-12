import DeskCore
import SwiftUI

/// Survey and ideation are the same shape — a door wrote a report, here is what it found — so they are one
/// destination with a source switch, rather than two screens differing only in which file they read.
struct ReportsScreen: View {
    @Bindable var model: ProjectWindowModel

    var body: some View {
        switch model.reportSource {
        case .survey: FindingsScreen(model: model)
        case .ideation: IdeationScreen(model: model)
        }
    }
}

/// Takes the place of each source's title, so the control that switches source never moves when you use it.
struct ReportSourcePicker: View {
    @Bindable var model: ProjectWindowModel

    var body: some View {
        Picker("", selection: $model.reportSource) {
            ForEach(ReportSource.allCases, id: \.self) { source in
                Text(source.title).tag(source)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
        .accessibilityLabel("Report source")
    }
}

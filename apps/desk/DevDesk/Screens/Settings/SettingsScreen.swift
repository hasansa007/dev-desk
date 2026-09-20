import DeskCore
import SwiftUI

struct SettingsScreen: View {
    @Bindable var model: ProjectWindowModel

    var body: some View {
        HStack(spacing: 0) {
            sectionList
            ScrollView {
                pane
                    .frame(maxWidth: 900, alignment: .leading)
                    .padding(.vertical, 20)
                    .padding(.horizontal, 24)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private var sectionList: some View {
        // Grouped by where a setting applies (ADR 0046): every project on this Mac, or only this one.
        VStack(alignment: .leading, spacing: 0) {
            groupLabel("This Mac")
            ForEach(SettingsSection.allCases.filter { !$0.isProjectScoped }, id: \.self) { section in
                sectionRow(section)
            }
            groupLabel("This project").padding(.top, 14)
            ForEach(SettingsSection.allCases.filter(\.isProjectScoped), id: \.self) { section in
                sectionRow(section)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 10)
        .frame(width: 230, alignment: .top)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(DeskColor.sidebar)   // navigation layer (the three-layer rule)
        .overlay(alignment: .trailing) { Rectangle().fill(DeskColor.divider).frame(width: 1) }
    }

    private func groupLabel(_ text: String) -> some View {
        Text(text)
            .font(DeskFont.secondary.weight(.semibold))
            .foregroundStyle(DeskColor.faintInk)
            .padding(.horizontal, 10)
            .padding(.bottom, 4)
    }

    private func sectionRow(_ section: SettingsSection) -> some View {
        let isSelected = model.settingsSection == section
        return Button { model.settingsSection = section } label: {
            Text(section.title)
                .font(DeskFont.body)
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundStyle(isSelected ? DeskColor.onColorInk : DeskColor.navInk)
                .padding(.vertical, 7)
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(isSelected ? DeskColor.accent : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    @ViewBuilder private var pane: some View {
        switch model.settingsSection {
        case .general: GeneralPane(model: model)
        case .appearance: AppearancePane()
        case .agentsAndDefaults: AgentsAndDefaultsPane(model: model)
        case .startWith: StartWithPane()
        case .accountsAndConnections: AccountsPane(model: model)
        case .notifications: NotificationsPane()
        case .execution: ExecutionPane()
        case .work: WorkSettingsPane(model: model)
        case .projectOverrides: ProjectOverridesPane(model: model)
        case .runProject: RunProjectPane(model: model)
        }
    }
}

struct SettingsScreen_Previews: PreviewProvider {
    static var previews: some View {
        SettingsPreviewHost()
            .frame(width: 1100, height: 780)
    }

    private struct SettingsPreviewHost: View {
        @State private var model = ProjectWindowModel(ref: .sample(.studyHub), source: SampleDataSource(project: .studyHub))

        var body: some View {
            SettingsScreen(model: model)
                .task {
                    await model.load()
                    model.settingsSection = .agentsAndDefaults
                }
        }
    }
}

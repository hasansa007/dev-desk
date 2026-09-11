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
        VStack(spacing: 0) {
            ForEach(SettingsSection.allCases, id: \.self) { section in
                sectionRow(section)
            }
        }
        .padding(10)
        .frame(width: 230, alignment: .top)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(DeskColor.surface)
        .overlay(alignment: .trailing) { Rectangle().fill(DeskColor.divider).frame(width: 1) }
    }

    private func sectionRow(_ section: SettingsSection) -> some View {
        let isSelected = model.settingsSection == section
        return Button { model.settingsSection = section } label: {
            Text(section.title)
                .font(DeskFont.body)
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundStyle(isSelected ? Color.white : DeskColor.navInk)
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
        case .general: GeneralPane()
        case .appearance: AppearancePane()
        case .agentsAndDefaults: AgentsAndDefaultsPane(model: model)
        case .accountsAndConnections: AccountsPane(model: model)
        case .notifications: NotificationsPane()
        case .execution: ExecutionPane()
        case .projectOverrides: ProjectOverridesPane(model: model)
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

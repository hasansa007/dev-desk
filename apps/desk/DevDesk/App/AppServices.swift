import DeskCore
import SwiftUI

@MainActor
enum AppServices {
    static let recents = RecentProjectsStore()
}

private struct ProjectModelKey: FocusedValueKey {
    typealias Value = ProjectWindowModel
}

extension FocusedValues {
    var projectModel: ProjectWindowModel? {
        get { self[ProjectModelKey.self] }
        set { self[ProjectModelKey.self] = newValue }
    }
}

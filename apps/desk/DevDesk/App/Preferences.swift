import DeskCore
import SwiftUI

enum PreferenceKey {
    static let appearance = "desk.appearance"
    static let terminalFontSize = "desk.terminalFontSize"
    static let showSamples = "desk.showSamples"
    static let defaultConnection = "desk.defaultConnection"
    static let notifyDecisions = "desk.notifyDecisions"
    static let notifyCompletion = "desk.notifyCompletion"
    static let notifyFailures = "desk.notifyFailures"
    static let worktreeLocation = "desk.worktreeLocation"

    static func connectionOverride(_ ref: ProjectRef) -> String { "desk.connectionOverride.\(ref.id)" }
}

enum AppearanceChoice: String, CaseIterable {
    case system, light, dark

    var title: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

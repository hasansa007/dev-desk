import SwiftUI

/// The two ratings an issue carries as `impact:` / `complexity:` labels (ADR 0020), as one picker — so the Add Task
/// sheet and the dialog's edit offer the same values in the same shape rather than two spellings of one idea.
enum TaskRatings {
    /// What "nobody has rated this" looks like in a picker, which cannot hold nil.
    static let none = "—"
    static let all = [none, "High", "Medium", "Low"]

    /// The rating itself, or nil for the unrated row.
    static func value(_ choice: String) -> String? { choice == none ? nil : choice }

    static func picker(selection: Binding<String>) -> some View {
        Picker("", selection: selection) {
            ForEach(all, id: \.self) { Text($0).tag($0) }
        }
        .labelsHidden()
        .frame(width: 140, alignment: .leading)
    }
}

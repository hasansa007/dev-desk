import DeskCore
import SwiftUI

/// Work's filter row (ADR 0046): priority, type and tag. The milestone is chosen in Work's list, not here.
struct TaskFilterBar: View {
    @Bindable var model: ProjectWindowModel

    var body: some View {
        // No milestone picker: Work's list on the left is the milestone choice (ADR 0046 decision 13).
        // The shared second row and its one chip (ADR 0046 decisions 14, 15): filter groups, any or none on.
        ScreenBar {
            ChipGroupLabel("Priority")
            ForEach(TaskFilter.priorityOrder, id: \.self) { p in
                FilterChip(p, isOn: model.taskFilter.priorities.contains(p), tone: TaskFilterBar.tone(p),
                           count: count { $0.priority == p }) {
                    toggle(&model.taskFilter.priorities, p)
                }
            }
            FilterChip("None", isOn: model.taskFilter.priorities.contains(TaskFilter.unprioritised),
                       count: count { $0.priority == nil }) {
                toggle(&model.taskFilter.priorities, TaskFilter.unprioritised)
            }
            ChipSeparator()
            ChipGroupLabel("Type")
            ForEach(TaskKind.allCases, id: \.self) { kind in
                FilterChip(kind.rawValue, isOn: model.taskFilter.kinds.contains(kind), count: count { $0.kind == kind }) {
                    toggle(&model.taskFilter.kinds, kind)
                }
            }
            ChipSeparator()
            ChipGroupLabel("Tag")
            ForEach(TaskFilter.tagLabels, id: \.self) { tag in
                FilterChip(tag.capitalized, isOn: model.taskFilter.tags.contains(tag), count: count { $0.labels.contains(tag) }) {
                    toggle(&model.taskFilter.tags, tag)
                }
            }
        } trailing: {
            if model.taskFilter.isActive { ChipClear { model.taskFilter = TaskFilter() } }
        }
    }

    /// Open issues in the selected milestone that a chip would keep — what turning it on leaves, before other filters.
    private func count(_ matches: (DeskTask) -> Bool) -> Int {
        model.tasks.filter { $0.issueNumber != nil && $0.column != .done && model.inWorkScope($0) && matches($0) }.count
    }

    private func toggle<T: Hashable>(_ set: inout Set<T>, _ value: T) {
        if set.contains(value) { set.remove(value) } else { set.insert(value) }
    }

    /// Priority is the one strong colour on a card: P0 red, P1 amber, P2 blue, P3 grey.
    static func tone(_ priority: String) -> StatusTone {
        switch priority {
        case "P0": return .failed
        case "P1": return .waiting
        case "P2": return .info
        default: return .neutral
        }
    }
}

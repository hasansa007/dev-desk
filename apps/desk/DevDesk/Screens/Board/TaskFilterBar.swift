import DeskCore
import SwiftUI

/// Work's filter row (ADR 0046): priority, type and tag. The milestone is chosen in Work's list, not here.
struct TaskFilterBar: View {
    @Bindable var model: ProjectWindowModel

    var body: some View {
        // No milestone picker: Work's list on the left is the milestone choice (ADR 0046 decision 13).
        HStack(spacing: 14) {
            group("Priority") {
                ForEach(TaskFilter.priorityOrder, id: \.self) { p in
                    chip(p, on: model.taskFilter.priorities.contains(p), tone: TaskFilterBar.tone(p)) {
                        toggle(&model.taskFilter.priorities, p)
                    }
                }
                chip("None", on: model.taskFilter.priorities.contains(TaskFilter.unprioritised), tone: nil) {
                    toggle(&model.taskFilter.priorities, TaskFilter.unprioritised)
                }
            }
            group("Type") {
                ForEach(TaskKind.allCases, id: \.self) { kind in
                    chip(kind.rawValue, on: model.taskFilter.kinds.contains(kind), tone: nil) {
                        toggle(&model.taskFilter.kinds, kind)
                    }
                }
            }
            group("Tag") {
                ForEach(TaskFilter.tagLabels, id: \.self) { tag in
                    chip(tag.capitalized, on: model.taskFilter.tags.contains(tag), tone: nil) {
                        toggle(&model.taskFilter.tags, tag)
                    }
                }
            }
            Spacer(minLength: 0)
            if model.taskFilter.isActive {
                Button("Clear filters") { model.taskFilter = TaskFilter() }
                    .buttonStyle(.plain)
                    .font(DeskFont.secondary)
                    .foregroundStyle(DeskColor.accent)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(DeskColor.canvas)   // content layer, like the header above it
        .overlay(alignment: .bottom) { Rectangle().fill(DeskColor.divider).frame(height: 1) }
    }

    private func group<Content: View>(_ label: String, @ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 4) {
            Text(label).font(DeskFont.secondary).foregroundStyle(DeskColor.mutedInk)
            content()
        }
    }

    private func chip(_ label: String, on: Bool, tone: StatusTone?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let tone { Circle().fill(DeskColor.tone(tone).dot).frame(width: 6, height: 6) }
                Text(label).font(.system(size: 11.5, weight: on ? .semibold : .regular))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .foregroundStyle(on ? DeskColor.surface : DeskColor.ink)
            .background(Capsule().fill(on ? DeskColor.ink : DeskColor.surface))
            .overlay(Capsule().stroke(on ? DeskColor.ink : DeskColor.divider, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
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

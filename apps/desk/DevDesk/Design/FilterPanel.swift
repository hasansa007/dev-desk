import DeskCore
import SwiftUI

/// One choice in a filter group (ADR 0046 decision 18).
struct FilterOption: Identifiable {
    let id: String
    var label: String
    var isOn: Bool
    var tone: StatusTone? = nil
    var count: String? = nil
    /// A small badge before the label — Work's "Now" on the Working now milestone.
    var badge: String? = nil
    /// The full text on hover, when the label is cut to fit.
    var help: String? = nil
    /// Right-click actions on the chip or menu item.
    var actions: [FilterAction] = []

    var isDim: Bool { !isOn && count == "0" }
}

struct FilterAction: Identifiable {
    let title: String
    let run: () -> Void
    var id: String { title }
}

/// A group of choices: a pick-one group keeps one on; a filter group may have any or none.
struct FilterGroup: Identifiable {
    enum Kind { case pickOne, filter }

    let key: String
    var title: String
    var kind: Kind
    var options: [FilterOption]
    let toggle: (String) -> Void
    /// The group's own ⓘ: what it narrows by, beside its title (ADR 0046 decision 17).
    var guide: (title: String, lines: [String])? = nil
    /// Beside the title: a control that belongs to the group, like Work's Run roadmap.
    var accessory: AnyView? = nil
    /// Under the options: one link, like Diagrams' "Draw another flow…".
    var footer: (title: String, run: () -> Void)? = nil
    /// Cut long labels (milestone names) to this width; the rest is on hover.
    var maxLabelWidth: CGFloat? = nil
    var id: String { key }

    var onCount: Int { options.filter(\.isOn).count }
}

/// Every tab's left panel (ADR 0046 decision 18): a header the height of the tab's, then the groups that narrow the
/// view — each as chips by default, or as a menu, the choice remembered per group. Collapsed, it is a thin strip
/// that still shows how many filters are on.
struct FilterPanel: View {
    let title: String
    var guide: (title: String, lines: [String])? = nil
    let storageKey: String
    var groups: [FilterGroup]
    /// Filters (not pick-one choices) that are on, and how to clear them; nil hides Clear all.
    var clear: (summary: String, count: Int, run: () -> Void)? = nil

    @AppStorage private var isCollapsed: Bool
    @AppStorage("filterPanelMenus") private var menusRaw = ""
    @AppStorage("filterPanelFolded") private var foldedRaw = ""

    init(title: String, guide: (title: String, lines: [String])? = nil, storageKey: String, groups: [FilterGroup],
         clear: (summary: String, count: Int, run: () -> Void)? = nil) {
        self.title = title
        self.guide = guide
        self.storageKey = storageKey
        self.groups = groups
        self.clear = clear
        _isCollapsed = AppStorage(wrappedValue: false, "filterPanelCollapsed.\(storageKey)")
    }

    static let width: CGFloat = 270

    var body: some View {
        Group {
            if isCollapsed { rail } else { panel }
        }
        .background(DeskColor.sidebar)
        .overlay(alignment: .trailing) { Rectangle().fill(DeskColor.divider).frame(width: 1) }
    }

    // MARK: - Collapsed

    private var rail: some View {
        Button { isCollapsed = false } label: {
            VStack(spacing: 10) {
                Image(systemName: "sidebar.left").foregroundStyle(DeskColor.mutedInk)
                    .frame(width: 28, height: DeskMetric.screenHeaderHeight)
                if let clear, clear.count > 0 {
                    Text("\(clear.count)")
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Capsule().fill(DeskColor.accent))
                }
                Text(railTitle)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DeskColor.mutedInk)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: 220)
                    .rotationEffect(.degrees(-90))
                    .frame(width: 28, height: 220)
                Spacer()
            }
            .frame(width: 36)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(clear.map { $0.count > 0 ? "Show \(title) — \($0.summary) on" : "Show \(title)" } ?? "Show \(title)")
        .accessibilityLabel("Show \(title)")
    }

    /// What the strip says sideways: the first group's selection (the milestone, the kind) or the panel's name.
    private var railTitle: String {
        guard let first = groups.first else { return title }
        let on = first.options.filter(\.isOn).map(\.label)
        return on.isEmpty ? title : on.joined(separator: ", ")
    }

    // MARK: - Open

    private var panel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(DeskColor.ink).lineLimit(1)
                if let guide { ScreenGuideButton(part: title, guide: guide) }
                Spacer()
                Button { isCollapsed = true } label: {
                    Image(systemName: "sidebar.left").foregroundStyle(DeskColor.mutedInk)
                        .frame(width: 24, height: 24).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Hide this panel, for more room")
                .accessibilityLabel("Hide \(title)")
            }
            .padding(.horizontal, 14)
            .frame(height: DeskMetric.screenHeaderHeight)
            .overlay(alignment: .bottom) { Rectangle().fill(DeskColor.divider).frame(height: 1) }

            if let clear, clear.count > 0 {
                HStack {
                    Text(clear.summary).font(.system(size: 12)).foregroundStyle(DeskColor.secondaryInk).lineLimit(1)
                    Spacer()
                    Button("Clear all (\(clear.count))", action: clear.run)
                        .buttonStyle(.plain)
                        .font(.system(size: 12))
                        .foregroundStyle(DeskColor.accent)
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(DeskColor.accent.opacity(0.06))
                .overlay(alignment: .bottom) { Rectangle().fill(DeskColor.divider).frame(height: 1) }
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                        if index > 0 { Rectangle().fill(DeskColor.divider).frame(height: 1).padding(.top, 10) }
                        section(group)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 14)
            }
        }
        .frame(width: Self.width)
    }

    // MARK: - A group

    private var menus: Set<String> { Set(menusRaw.split(separator: ",").map(String.init)) }
    private var folded: Set<String> { Set(foldedRaw.split(separator: ",").map(String.init)) }

    private func flip(_ key: String, in raw: inout String) {
        var set = Set(raw.split(separator: ",").map(String.init))
        if set.contains(key) { set.remove(key) } else { set.insert(key) }
        raw = set.sorted().joined(separator: ",")
    }

    private func section(_ group: FilterGroup) -> some View {
        let isFolded = folded.contains(group.key)
        let asMenu = menus.contains(group.key)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Button { flip(group.key, in: &foldedRaw) } label: {
                    HStack(spacing: 6) {
                        Image(systemName: isFolded ? "chevron.right" : "chevron.down")
                            .font(.system(size: 9, weight: .bold)).foregroundStyle(DeskColor.faintInk).frame(width: 10)
                        Text(group.title).font(.system(size: 12, weight: .semibold)).foregroundStyle(DeskColor.secondaryInk)
                            .lineLimit(1).fixedSize()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(group.title), \(isFolded ? "folded" : "open")")
                if let guide = group.guide { ScreenGuideButton(part: group.title, guide: guide) }
                Spacer(minLength: 4)
                if group.kind == .filter, group.onCount > 0 {
                    Text("\(group.onCount) on").font(.system(size: 11.5, weight: .semibold)).foregroundStyle(DeskColor.accent)
                }
                if let accessory = group.accessory { accessory }
                // Chips or a menu: the same choices either way, remembered per group.
                Button { flip(group.key, in: &menusRaw) } label: {
                    Image(systemName: asMenu ? "square.grid.2x2" : "list.bullet")
                        .font(.system(size: 10.5)).foregroundStyle(DeskColor.faintInk)
                        .frame(width: 20, height: 20).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(asMenu ? "Show \(group.title) as chips" : "Show \(group.title) as a menu")
                .accessibilityLabel(asMenu ? "Show as chips" : "Show as a menu")
            }
            .padding(.top, 12)
            if !isFolded {
                if asMenu { menu(group) } else { chips(group) }
                if let footer = group.footer {
                    Button(footer.title, action: footer.run)
                        .buttonStyle(.plain)
                        .font(.system(size: 12))
                        .foregroundStyle(DeskColor.accent)
                        .padding(.top, 2)
                }
            }
        }
    }

    private func chips(_ group: FilterGroup) -> some View {
        FlowLayout(spacing: 6) {
            ForEach(group.options) { option in
                FilterChip(option.label, isOn: option.isOn, tone: option.tone, count: option.count,
                           badge: option.badge, maxLabelWidth: group.maxLabelWidth) { group.toggle(option.id) }
                    .opacity(option.isDim ? 0.5 : 1)
                    .help(option.help ?? "")
                    .contextMenu {
                        ForEach(option.actions) { action in Button(action.title, action: action.run) }
                    }
            }
        }
    }

    /// The menu form: a pick-one group reads as its choice; a filter group as what is on, or Any.
    private func menu(_ group: FilterGroup) -> some View {
        let on = group.options.filter(\.isOn).map(\.label)
        let label = on.isEmpty ? (group.kind == .filter ? "Any" : "None") : on.joined(separator: ", ")
        return Menu {
            ForEach(group.options) { option in
                Button { group.toggle(option.id) } label: {
                    let text = option.label + (option.badge.map { " · \($0)" } ?? "") + (option.count.map { "  (\($0))" } ?? "")
                    if option.isOn { Label(text, systemImage: "checkmark") } else { Text(text) }
                }
            }
            let actions = group.options.flatMap(\.actions)
            if !actions.isEmpty {
                Divider()
                ForEach(actions) { action in Button(action.title, action: action.run) }
            }
        } label: {
            HStack(spacing: 8) {
                Text(label).font(.system(size: 12.5)).foregroundStyle(DeskColor.ink).lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold)).foregroundStyle(DeskColor.faintInk)
            }
            .padding(.horizontal, 10)
            .frame(height: DeskMetric.chipHeight)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: DeskMetric.controlRadius).fill(DeskColor.surface))
            .overlay(RoundedRectangle(cornerRadius: DeskMetric.controlRadius).strokeBorder(DeskColor.divider))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .accessibilityLabel(group.title)
    }
}

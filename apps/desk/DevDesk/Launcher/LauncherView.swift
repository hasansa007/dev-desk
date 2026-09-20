import AppKit
import DeskCore
import SwiftUI

enum LauncherContext { case window, sheet }

struct LauncherView: View {
    let context: LauncherContext
    var onDismiss: () -> Void = {}

    @Environment(OpenProjectRegistry.self) private var registry
    @Environment(\.dismiss) private var dismissWindow
    @State private var selectedID: String?
    /// The recents live in UserDefaults, which SwiftUI does not observe; a removal bumps this so the list redraws.
    @State private var recentsRevision = 0
    @State private var activeSubSheet: SubSheet?
    @FocusState private var listFocused: Bool

    private enum SubSheet: Identifiable { case clone, create
        var id: Self { self }
    }

    var body: some View {
        switch context {
        case .sheet:
            SheetChrome(title: "Open project", confirmTitle: "Open", confirmDisabled: selectedRef == nil,
                        onCancel: onDismiss, onConfirm: openSelected) {
                launcherBody
            }
        case .window:
            // The content scrolls and Open is pinned below it. When the window was a fixed size this could be
            // one column with the button at the end of it; once it could be resized, shrinking the window
            // pushed Open off the bottom edge — a launcher you cannot launch from.
            VStack(alignment: .leading, spacing: 0) {
                ScrollView {
                    launcherBody
                        .padding(20)
                }
                Rectangle().fill(DeskColor.divider).frame(height: 1)
                HStack {
                    Spacer()
                    Button("Open") { openSelected() }
                        .buttonStyle(DeskButtonStyle(kind: .primary))
                        .keyboardShortcut(.defaultAction)
                        .disabled(selectedRef == nil)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
            }
            // Was a fixed 1000x540 window, which could not open at all on a 1024-wide display once its
            // chrome was counted. It is a starting size now, not a rule.
            .frame(minWidth: 360, idealWidth: 1000, maxWidth: .infinity,
                   minHeight: 360, idealHeight: 540, maxHeight: .infinity)
            // Dev Desk's layers, not the system window grey (2026-09-19): content ground, navigation title bar.
            .background(DeskColor.canvas)
            .toolbarBackground(DeskColor.sidebar, for: .windowToolbar)
            .toolbarBackground(.visible, for: .windowToolbar)
        }
    }

    private var launcherBody: some View {
        // Side by side while there is room for both columns, stacked when there is not: ViewThatFits picks,
        // so the same two lists work at 1000 pt and at 720.
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 18) {
                recentsColumn
                startColumn.frame(width: 320, alignment: .leading)
            }
            VStack(alignment: .leading, spacing: 16) {
                recentsColumn
                startColumn
            }
        }
        .sheet(item: $activeSubSheet) { sub in
            switch sub {
            case .clone: CloneRepositorySheet(onDismiss: { activeSubSheet = nil })
            case .create: CreateProjectSheet(onDismiss: { activeSubSheet = nil })
            }
        }
        .onAppear {
            if selectedID == nil { selectedID = rows.first { !$0.isMissing }?.id }
            listFocused = true
        }
    }

    private var recentsColumn: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                SectionLabel("Recent projects")
                Spacer()
                if !AppServices.recents.entries.isEmpty {
                    Button("Clear") { clearRecents() }
                        .buttonStyle(DeskButtonStyle(kind: .secondary, size: .mini))
                        .help("Removes every project from this list. No folder is touched.")
                }
            }
            recentList
            Text("Opening a project opens its own window and restores its last selected task and pane layout. Opening a project that is already open focuses that window instead of starting anything.")
                .font(DeskFont.secondary)
                .foregroundStyle(DeskColor.mutedInk)
                .lineSpacing(4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var startColumn: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Start something")
            startCard(title: "Open local folder…", detail: "Opens read-only. No agent is launched.", action: openLocalFolder)
            startCard(title: "Clone repository…", detail: "Choose a destination folder and branch.") { activeSubSheet = .clone }
            startCard(title: "Create new project…", detail: "Initialises a folder and PROJECT_MAP.md.") { activeSubSheet = .create }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Arrow keys move the selection, Return opens it; the list draws its own focus ring around the card.
    private var recentList: some View {
        let shape = RoundedRectangle(cornerRadius: DeskMetric.cardRadius)
        return VStack(spacing: 0) {
            if rows.isEmpty {
                // With the samples gone this box is empty on a fresh install, and an empty bordered
                // rectangle reads as a bug rather than as a state.
                Text("No projects yet. Open, clone or create one on the right.")
                    .font(DeskFont.secondary)
                    .foregroundStyle(DeskColor.mutedInk)
                    .padding(.vertical, 22)
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, item in
                if index > 0 { Rectangle().fill(DeskColor.rowDivider).frame(height: 1) }
                row(item)
            }
        }
        .clipShape(shape)
        .background(DeskColor.surface, in: shape)
        .overlay(shape.strokeBorder(listFocused ? DeskColor.accent : DeskColor.border))
        .overlay {
            if listFocused {
                shape.inset(by: -1.5).stroke(DeskColor.accent.opacity(0.14), lineWidth: 3)
            }
        }
        .focusable()
        .focused($listFocused)
        .focusEffectDisabled()
        .onKeyPress(.upArrow) {
            moveSelection(by: -1)
            return .handled
        }
        .onKeyPress(.downArrow) {
            moveSelection(by: 1)
            return .handled
        }
        .onKeyPress(.return) {
            openSelected()
            return .handled
        }
        .onKeyPress(.delete) {
            guard let item = rows.first(where: { $0.id == selectedID }) else { return .ignored }
            removeRecent(item)
            return .handled
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Recent projects")
    }

    private func row(_ item: LauncherRow) -> some View {
        let isSelected = selectedID == item.id
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).font(DeskFont.body.weight(.semibold)).foregroundStyle(DeskColor.ink)
                Text(item.path)
                    .font(DeskFont.mono(11))
                    .foregroundStyle(DeskColor.mutedInk)
            }
            Spacer(minLength: 8)
            if item.isMissing {
                Text("Missing").font(DeskFont.secondary).foregroundStyle(DeskColor.faintInk)
            } else {
                Text(registry.isOpen(item.ref) ? "Open · focuses its window" : "Open")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(DeskColor.tone(.info).foreground)
            }
        }
        .padding(.vertical, 11)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSelected ? DeskColor.tone(.info).fill : Color.clear)
        .contentShape(Rectangle())
        .opacity(item.isMissing ? 0.6 : 1)
        .onTapGesture(count: 2) { if !item.isMissing { open(item.ref) } }
        .onTapGesture(count: 1) { select(item) }
        .contextMenu {
            Button("Remove from Recent Projects") { removeRecent(item) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { select(item) }
        .accessibilityAction(named: "Open") { if !item.isMissing { open(item.ref) } }
    }

    private func startCard(title: String, detail: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).fontWeight(.semibold).foregroundStyle(DeskColor.ink)
                Text(detail).font(DeskFont.secondary).foregroundStyle(DeskColor.mutedInk)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(RoundedRectangle(cornerRadius: DeskMetric.cardRadius).strokeBorder(DeskColor.border))
            .contentShape(RoundedRectangle(cornerRadius: DeskMetric.cardRadius))
        }
        .buttonStyle(.plain)
    }

    private struct LauncherRow: Identifiable {
        let ref: ProjectRef
        let name: String
        let path: String
        let isMissing: Bool
        var id: String { ref.id }
    }

    /// Only projects that have actually been opened. The picker listed two built-in samples above these
    /// until 2026-09-20; a fresh install now shows the empty list and Start something, which is the truth.
    private var rows: [LauncherRow] {
        _ = recentsRevision
        return AppServices.recents.entries.map { entry in
            LauncherRow(ref: entry.ref, name: entry.name, path: entry.displayPath, isMissing: !isAvailable(entry.ref))
        }
    }

    private func isAvailable(_ ref: ProjectRef) -> Bool {
        guard case .local(let path) = ref else { return true }
        return FileManager.default.fileExists(atPath: path)
    }

    private var selectedRef: ProjectRef? { rows.first { $0.id == selectedID && !$0.isMissing }?.ref }

    /// Off the list only: the folder, its worktrees and anything open in it stay as they are.
    private func removeRecent(_ item: LauncherRow) {
        AppServices.recents.remove(item.ref)
        if selectedID == item.id { selectedID = nil }
        recentsRevision += 1
    }

    private func clearRecents() {
        AppServices.recents.entries.forEach { AppServices.recents.remove($0.ref) }
        selectedID = nil
        recentsRevision += 1
    }

    private func select(_ item: LauncherRow) {
        listFocused = true
        guard !item.isMissing else { return }
        selectedID = item.id
    }

    private func moveSelection(by step: Int) {
        let available = rows.filter { !$0.isMissing }
        guard !available.isEmpty else { return }
        guard let index = available.firstIndex(where: { $0.id == selectedID }) else {
            selectedID = (step > 0 ? available.first : available.last)?.id
            return
        }
        selectedID = available[min(max(index + step, 0), available.count - 1)].id
    }

    private func openSelected() {
        guard let ref = selectedRef else { return }
        open(ref)
    }

    /// The launcher is a step on the way to a project, not a place to leave open: as a window it closes
    /// behind the project it opened, the way a welcome window does. It comes back with Open Project (⌘O),
    /// and as a sheet it is dismissed by its host instead.
    private func open(_ ref: ProjectRef) {
        Workspace.shared.open(ref)
        onDismiss()
        if context == .window { dismissWindow() }
    }

    private func openLocalFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        open(.local(path: url.path))
    }
}

struct LauncherView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            LauncherView(context: .sheet)
                .frame(width: 1000)
            LauncherView(context: .window)
        }
        .environment(OpenProjectRegistry())
    }
}

import AppKit
import DeskCore
import SwiftUI

enum LauncherContext { case window, sheet }

struct LauncherView: View {
    let context: LauncherContext
    var onDismiss: () -> Void = {}

    @Environment(OpenProjectRegistry.self) private var registry
    @Environment(\.openWindow) private var openWindow
    @AppStorage(PreferenceKey.showSamples) private var showSamples = true
    @State private var selectedID: String?
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
            VStack(alignment: .leading, spacing: 0) {
                launcherBody
                HStack {
                    Spacer()
                    Button("Open") { openSelected() }
                        .buttonStyle(DeskButtonStyle(kind: .primary))
                        .keyboardShortcut(.defaultAction)
                        .disabled(selectedRef == nil)
                }
                .padding(.top, 14)
            }
            .padding(20)
            .frame(width: 1000, height: 540)
        }
    }

    private var launcherBody: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 9) {
                SectionLabel("Recent projects")
                recentList
                Text("Opening a project opens its own window and restores its last selected task and pane layout. Opening a project that is already open focuses that window instead of starting anything.")
                    .font(DeskFont.secondary)
                    .foregroundStyle(DeskColor.mutedInk)
                    .lineSpacing(4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 10) {
                SectionLabel("Start something")
                startCard(title: "Open local folder…", detail: "Opens read-only. No agent is launched.", action: openLocalFolder)
                startCard(title: "Clone repository…", detail: "Choose a destination folder and branch.") { activeSubSheet = .clone }
                startCard(title: "Create new project…", detail: "Initialises a folder and PROJECT_MAP.md.") { activeSubSheet = .create }
            }
            .frame(width: 320, alignment: .leading)
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

    /// Arrow keys move the selection, Return opens it; the list draws its own focus ring around the card.
    private var recentList: some View {
        let shape = RoundedRectangle(cornerRadius: DeskMetric.cardRadius)
        return VStack(spacing: 0) {
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
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Recent projects")
    }

    private func row(_ item: LauncherRow) -> some View {
        let isSelected = selectedID == item.id
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.name).font(DeskFont.body.weight(.semibold)).foregroundStyle(DeskColor.ink)
                    if item.isSample { PropertyChip("Sample") }
                }
                Text(item.path)
                    .font(DeskFont.mono(11))
                    .foregroundStyle(DeskColor.mutedInk)
            }
            Spacer(minLength: 8)
            if item.isMissing {
                Text("Missing").font(DeskFont.secondary).foregroundStyle(DeskColor.faintInk)
            } else {
                Text(registry.isOpen(item.ref) ? "Open · focuses its window" : "Open")
                    .font(.system(size: 11))
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
        let isSample: Bool
        let isMissing: Bool
        var id: String { ref.id }
    }

    private var rows: [LauncherRow] {
        var list: [LauncherRow] = []
        if showSamples {
            list += SampleProject.allCases.map {
                LauncherRow(ref: .sample($0), name: $0.title, path: $0.displayPath, isSample: true, isMissing: false)
            }
        }
        list += AppServices.recents.entries.map { entry in
            LauncherRow(ref: entry.ref, name: entry.name, path: entry.displayPath, isSample: false, isMissing: !isAvailable(entry.ref))
        }
        return list
    }

    private func isAvailable(_ ref: ProjectRef) -> Bool {
        guard case .local(let path) = ref else { return true }
        return FileManager.default.fileExists(atPath: path)
    }

    private var selectedRef: ProjectRef? { rows.first { $0.id == selectedID && !$0.isMissing }?.ref }

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

    private func open(_ ref: ProjectRef) {
        openWindow(value: ref)
        onDismiss()
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

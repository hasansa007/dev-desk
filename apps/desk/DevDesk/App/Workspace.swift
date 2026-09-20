import DeskCore
import Observation
import SwiftUI

/// Every open project, and which one you are looking at (ADR 0050). One window holds them all now, so this is
/// app-wide state and not a window's: the strip switches the selection, and a project that is not selected goes
/// on loading, running and asking for you in the badge on its own icon.
@MainActor
@Observable
final class Workspace {
    /// App-wide by construction — there is one window — so the menu bar, a sheet and snapshot mode can all
    /// open a project without a view having to hand the workspace down to them.
    static let shared = Workspace()

    /// The strip, in order, top to bottom.
    private(set) var refs: [ProjectRef] = []
    /// Nil is Home: what needs you across projects.
    private(set) var selection: ProjectRef?
    /// The Open project dialog, raised by the strip's `+` and by ⌘O.
    var isOpeningProject = false
    /// Settings with no project behind it: what ⌘, opens on Home, holding only the app-wide options.
    var isShowingSettings = false

    private var contexts: [String: ProjectContext] = [:]
    /// Kept in step so the launcher can still grey out a project that is already open.
    private var registry: OpenProjectRegistry?

    private static let refsKey = "desk.workspace.projects"
    private static let selectionKey = "desk.workspace.selection"

    private init() {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: Self.refsKey),
           let stored = try? JSONDecoder().decode([ProjectRef].self, from: data) {
            refs = stored
        }
        if let id = defaults.string(forKey: Self.selectionKey) {
            selection = refs.first { $0.id == id }
        }
    }

    func attach(registry: OpenProjectRegistry) {
        self.registry = registry
        refs.forEach { registry.windowOpened($0) }
    }

    // MARK: - The strip

    /// Live for every project in the strip, not only the selected one — that is the whole promise of the strip,
    /// and what lets a badge say a run is waiting for you somewhere else.
    var contextsInStripOrder: [ProjectContext] { refs.map(context) }

    var selected: ProjectContext? { selection.map(context) }

    var isHome: Bool { selection == nil }

    func context(for ref: ProjectRef) -> ProjectContext {
        if let existing = contexts[ref.id] { return existing }
        let made = ProjectContext(ref: ref)
        contexts[ref.id] = made
        return made
    }

    /// Adds the project to the strip if it is new, and selects it either way — opening a project you already
    /// have open is a request to look at it, not a second copy of it.
    func open(_ ref: ProjectRef) {
        if !refs.contains(ref) {
            refs.append(ref)
            registry?.windowOpened(ref)
            persistRefs()
        }
        select(ref)
        isOpeningProject = false
    }

    func select(_ ref: ProjectRef?) {
        selection = ref
        for context in contexts.values { context.isFrontmost = context.ref == ref }
        UserDefaults.standard.set(ref?.id ?? "", forKey: Self.selectionKey)
    }

    /// Takes the project off the strip and ends its sessions, the way closing its window used to. The selection
    /// falls to the neighbour that took its place, or Home when it was the last one.
    func close(_ ref: ProjectRef) {
        guard let index = refs.firstIndex(of: ref) else { return }
        refs.remove(at: index)
        contexts.removeValue(forKey: ref.id)?.end()
        registry?.windowClosed(ref)
        persistRefs()
        if selection == ref { select(refs.indices.contains(index) ? refs[index] : refs.last) }
    }

    // MARK: - Home

    /// Every session waiting on an answer, anywhere. Home's headline, and why the strip is worth having.
    var waitingTotal: Int { contextsInStripOrder.reduce(0) { $0 + $1.waitingCount } }

    var runningProjectCount: Int { contextsInStripOrder.count(where: \.isRunning) }

    /// The project Home draws widest: the one with most waiting on it, and failing that the one that is running.
    /// With nothing anywhere it is the selected project, so Home is never an empty screen with three equal cards.
    var focusContext: ProjectContext? {
        let all = contextsInStripOrder
        if let waiting = all.filter({ $0.waitingCount > 0 }).max(by: { $0.waitingCount < $1.waitingCount }) { return waiting }
        return all.first(where: \.isRunning) ?? all.first
    }

    private func persistRefs() {
        guard let data = try? JSONEncoder().encode(refs) else { return }
        UserDefaults.standard.set(data, forKey: Self.refsKey)
    }
}

import DeskCore
import SwiftUI

/// The dock's own state, kept per project rather than per window: one window now holds every project, so an
/// open dock in one and a closed dock in another are two answers to the same question and both must survive
/// switching between them. Open and height are written to defaults; which tiles are up is not — the sessions
/// they name do not outlive the app.
@MainActor
@Observable
final class SessionDockState {
    static let shared = SessionDockState()

    /// Four terminals side by side is where a tile stops being able to name its own session; a fifth pushes
    /// the oldest one out rather than shrinking all of them past reading.
    static let maxTiles = 4

    private var openByProject: [String: Bool] = [:]
    private var heightByProject: [String: Double] = [:]
    /// Nil means "never chosen here", which is not the same as "chosen nothing": the first is what opens on
    /// the live sessions, the second is a dock the developer has emptied on purpose.
    private var shownByProject: [String: [String]] = [:]

    func isOpen(_ ref: ProjectRef) -> Bool {
        if let open = openByProject[ref.id] { return open }
        let stored = UserDefaults.standard.object(forKey: Self.openKey(ref)) as? Bool ?? false
        openByProject[ref.id] = stored
        return stored
    }

    func setOpen(_ open: Bool, for ref: ProjectRef) {
        openByProject[ref.id] = open
        UserDefaults.standard.set(open, forKey: Self.openKey(ref))
    }

    func height(for ref: ProjectRef) -> Double {
        if let height = heightByProject[ref.id] { return height }
        let stored = UserDefaults.standard.object(forKey: Self.heightKey(ref)) as? Double ?? DeskMetric.runsPanelHeight
        let clamped = min(max(stored, DeskMetric.runsHeightRange.lowerBound), DeskMetric.runsHeightRange.upperBound)
        heightByProject[ref.id] = clamped
        return clamped
    }

    func setHeight(_ height: Double, for ref: ProjectRef) {
        heightByProject[ref.id] = height
        UserDefaults.standard.set(height, forKey: Self.heightKey(ref))
    }

    /// The tiles up right now, in the order they were raised, and only those whose session still exists — a
    /// door run cleared elsewhere must not leave a tile hosting nothing.
    func shown(for ref: ProjectRef, among ids: [String]) -> [String] {
        guard let chosen = shownByProject[ref.id] else {
            return Array(ids.prefix(Self.maxTiles))
        }
        return chosen.filter(ids.contains)
    }

    func isShown(_ id: String, for ref: ProjectRef, among ids: [String]) -> Bool {
        shown(for: ref, among: ids).contains(id)
    }

    func toggle(_ id: String, for ref: ProjectRef, among ids: [String]) {
        var chosen = shown(for: ref, among: ids)
        if let index = chosen.firstIndex(of: id) { chosen.remove(at: index) } else { chosen.append(id) }
        shownByProject[ref.id] = Array(chosen.suffix(Self.maxTiles))
    }

    /// A session that has just been started or resumed takes a tile whether or not the dock had one free: it
    /// is the thing that was just asked for, so the oldest tile yields to it.
    func raise(_ id: String, for ref: ProjectRef, among ids: [String]) {
        var chosen = shown(for: ref, among: ids).filter { $0 != id }
        chosen.append(id)
        shownByProject[ref.id] = Array(chosen.suffix(Self.maxTiles))
    }

    /// Where ⌘] last landed in this project's dock, so the next press moves on from it.
    private var currentByProject: [String: String] = [:]

    func current(for ref: ProjectRef) -> String? { currentByProject[ref.id] }

    /// A step lands on a session and shows it: already a tile, it stays where it is; otherwise it is raised, and
    /// the oldest tile yields as it would to any session asked for.
    func step(to id: String, for ref: ProjectRef, among ids: [String]) {
        currentByProject[ref.id] = id
        if !isShown(id, for: ref, among: ids) { raise(id, for: ref, among: ids) }
    }

    func hide(_ id: String, for ref: ProjectRef, among ids: [String]) {
        shownByProject[ref.id] = shown(for: ref, among: ids).filter { $0 != id }
    }

    private static func openKey(_ ref: ProjectRef) -> String { "desk.dock.open.\(ref.id)" }
    private static func heightKey(_ ref: ProjectRef) -> String { "desk.dock.height.\(ref.id)" }
}

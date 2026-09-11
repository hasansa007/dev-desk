import Foundation

public struct RecentProject: Codable, Hashable, Identifiable {
    public var ref: ProjectRef
    public var name: String
    public var displayPath: String
    public var openedAt: Date
    public var id: String { ref.id }
    public init(ref: ProjectRef, name: String, displayPath: String, openedAt: Date) {
        self.ref = ref
        self.name = name
        self.displayPath = displayPath
        self.openedAt = openedAt
    }
}

public final class RecentProjectsStore {
    private let defaults: UserDefaults
    private let key: String
    private let limit: Int

    public init(defaults: UserDefaults = .standard, key: String = "desk.recentProjects", limit: Int = 10) {
        self.defaults = defaults
        self.key = key
        self.limit = limit
    }

    public var entries: [RecentProject] {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([RecentProject].self, from: data) else { return [] }
        return decoded
    }

    /// Moves the project to the front; samples are never recorded because the picker lists them itself.
    public func record(_ ref: ProjectRef, name: String, displayPath: String, at date: Date = Date()) {
        guard !ref.isSample else { return }
        var list = entries.filter { $0.ref != ref }
        list.insert(RecentProject(ref: ref, name: name, displayPath: displayPath, openedAt: date), at: 0)
        save(Array(list.prefix(limit)))
    }

    public func remove(_ ref: ProjectRef) { save(entries.filter { $0.ref != ref }) }

    private func save(_ list: [RecentProject]) {
        if let data = try? JSONEncoder().encode(list) { defaults.set(data, forKey: key) }
    }
}

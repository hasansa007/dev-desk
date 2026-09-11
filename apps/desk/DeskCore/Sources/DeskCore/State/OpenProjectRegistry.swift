import Observation

@MainActor
@Observable
public final class OpenProjectRegistry {
    public private(set) var openRefs: Set<ProjectRef> = []
    public init() {}
    public func windowOpened(_ ref: ProjectRef) { openRefs.insert(ref) }
    public func windowClosed(_ ref: ProjectRef) { openRefs.remove(ref) }
    public func isOpen(_ ref: ProjectRef) -> Bool { openRefs.contains(ref) }
}

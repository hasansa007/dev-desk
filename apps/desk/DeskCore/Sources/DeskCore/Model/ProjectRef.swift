public enum SampleProject: String, Codable, CaseIterable, Hashable {
    case studyHub
    case devDesk

    public var title: String { self == .studyHub ? "StudyHub" : "dev-desk" }
    public var displayPath: String { self == .studyHub ? "~/code/studyhub" : "~/code/dev-desk" }
}

public enum ProjectRef: Hashable, Codable, Identifiable {
    case sample(SampleProject)
    case local(path: String)

    public var id: String {
        switch self {
        case .sample(let project): return "sample:\(project.rawValue)"
        case .local(let path): return "local:\(path)"
        }
    }

    public var isSample: Bool {
        if case .sample = self { return true }
        return false
    }
}

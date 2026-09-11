import Foundation

public protocol ProjectDataSource {
    func load() async throws -> ProjectSnapshot
}

public enum DataSources {
    public static func make(for ref: ProjectRef) -> ProjectDataSource {
        switch ref {
        case .sample(let project): return SampleDataSource(project: project)
        case .local(let path): return LocalGitDataSource(root: URL(fileURLWithPath: path))
        }
    }
}

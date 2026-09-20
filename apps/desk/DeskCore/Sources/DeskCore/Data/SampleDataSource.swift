public struct SampleDataSource: ProjectDataSource {
    public let project: SampleProject
    public init(project: SampleProject) { self.project = project }

    public func load() async throws -> ProjectSnapshot {
        switch project {
        case .studyHub: return SampleData.studyHub()
        case .devDesk: return SampleData.devDesk()
        }
    }
}

public enum SampleData {}  // extended by the three SampleData+*.swift files

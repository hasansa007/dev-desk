public struct SampleDataSource: ProjectDataSource {
    public let project: SampleProject
    public init(project: SampleProject) { self.project = project }

    public func load() async throws -> ProjectSnapshot {
        switch project {
        case .studyHub: return SampleData.studyHub()
        case .devSkill: return SampleData.devSkill()
        }
    }
}

public enum SampleData {}  // extended by the three SampleData+*.swift files

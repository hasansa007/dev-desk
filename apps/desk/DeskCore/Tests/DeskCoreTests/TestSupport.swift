import Foundation
@testable import DeskCore

struct FixedSource: ProjectDataSource {
    let snapshot: ProjectSnapshot
    func load() async throws -> ProjectSnapshot { snapshot }
}

struct FailingSource: ProjectDataSource {
    let message: String
    func load() async throws -> ProjectSnapshot {
        throw NSError(domain: "DeskCoreTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}

@MainActor
func waitUntil(_ condition: @MainActor () -> Bool) async {
    let deadline = Date().addingTimeInterval(2)
    while !condition(), Date() < deadline {
        await Task.yield()
    }
}

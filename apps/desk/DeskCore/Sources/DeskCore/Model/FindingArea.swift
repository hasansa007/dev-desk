import Foundation

/// What part of the project a finding is in. A survey report does not say — but it does say where it looked,
/// and a path is enough to tell a screen from a test from a workflow. Derived, never invented: a finding with
/// no source locations has no area, and says so with a dash rather than a guess.
public enum FindingArea: String, CaseIterable, Hashable {
    case ui = "UI"
    case tests = "Tests"
    case logic = "Logic"
    case data = "Data"
    case ci = "CI"
    case config = "Config"
    case docs = "Docs"

    /// Which area wins when a finding touches several. Ordered by where the defect most likely lives: a
    /// change spanning three screens and one coordinator is a UI finding, not a coordinator one.
    static let precedence: [FindingArea] = [.ui, .logic, .data, .tests, .ci, .config, .docs]

    /// The area one path belongs to. Matched in this order — a test that renders a view is still a test, and
    /// a workflow that lints Swift is still CI.
    public static func of(path: String) -> FindingArea? {
        let file = path.split(separator: "/").last.map(String.init) ?? path
        let name = file.split(separator: ":").first.map(String.init) ?? file   // "View.swift:31" → "View.swift"
        // A leading slash, so "/tests/" matches a path that starts with the folder as well as one that
        // contains it. Without it "Stubs/…Stub.swift" read as ordinary source.
        let lower = "/" + path.lowercased()
        let leaf = name.lowercased()

        if lower.hasPrefix("/.github/") || lower.contains("/workflows/") || leaf == "jenkinsfile"
            || leaf == "fastfile" || leaf.hasPrefix(".gitlab-ci") || leaf.hasPrefix("azure-pipelines") {
            return .ci
        }
        if lower.contains("/tests/") || lower.contains("/test/") || lower.contains("/__tests__/")
            || lower.contains("/stubs/") || lower.contains("/mocks/") || leaf.hasPrefix("test_")
            || ["tests.swift", "test.swift", "spec.rb"].contains(where: { leaf.hasSuffix($0) })
            || [".test.ts", ".test.tsx", ".test.js", ".spec.ts", ".spec.tsx", ".spec.js", "_test.go", "_test.py"]
                .contains(where: { leaf.hasSuffix($0) }) {
            return .tests
        }
        if lower.contains("/docs/") || [".md", ".mdx", ".rst", ".txt"].contains(where: { leaf.hasSuffix($0) }) {
            return .docs
        }
        if [".tsx", ".jsx", ".vue", ".svelte", ".css", ".scss", ".html", ".storyboard", ".xib"]
            .contains(where: { leaf.hasSuffix($0) })
            || ["view.swift", "screen.swift", "viewcontroller.swift", "cell.swift"].contains(where: { leaf.hasSuffix($0) })
            || ["/views/", "/screens/", "/components/", "/ui/", "/pages/"].contains(where: { lower.contains($0) }) {
            return .ui
        }
        if ["/models/", "/store/", "/stores/", "/db/", "/migrations/", "/persistence/"].contains(where: { lower.contains($0) })
            || ["repository.swift", "datasource.swift", "store.swift", ".sql"].contains(where: { leaf.hasSuffix($0) }) {
            return .data
        }
        if [".yml", ".yaml", ".json", ".toml", ".plist", ".xcconfig", ".lock", ".cfg", ".ini"]
            .contains(where: { leaf.hasSuffix($0) })
            || ["package.swift", "podfile", "dockerfile", "makefile"].contains(leaf) {
            return .config
        }
        // Everything else that looks like source is the work the app does.
        return leaf.contains(".") ? .logic : nil
    }

    /// The area a set of locations is mostly in: the commonest, ties broken by `precedence`.
    public static func of(paths: [String]) -> FindingArea? {
        let areas = paths.compactMap { of(path: $0) }
        guard !areas.isEmpty else { return nil }
        let counts = areas.reduce(into: [FindingArea: Int]()) { $0[$1, default: 0] += 1 }
        return counts.max { left, right in
            if left.value != right.value { return left.value < right.value }
            let leftRank = precedence.firstIndex(of: left.key) ?? precedence.count
            let rightRank = precedence.firstIndex(of: right.key) ?? precedence.count
            return leftRank > rightRank
        }?.key
    }
}

extension Finding {
    /// Where this finding is, from where it was found.
    public var area: FindingArea? { FindingArea.of(paths: locations) }
}

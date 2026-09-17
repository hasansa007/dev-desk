import Foundation

/// The advisory `.dev/<slug>.json` state dev.py writes; git wins any disagreement with it.
struct PipelineState: Equatable {
    var phase: Int
    var phaseGroup: String? = nil
    var tier: String? = nil
    var phasesCompleted: [Int] = []

    static let stages: [(name: String, phases: ClosedRange<Int>)] = [
        ("Investigated", 1...4), ("Planned", 5...8), ("Implementing", 9...10), ("Verified", 11...13),
    ]

    private static let safeScalars = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-".unicodeScalars)

    /// dev.py's slugify, per code point: a branch's slashes must not nest directories.
    static func slug(_ branch: String) -> String {
        String(branch.unicodeScalars.map { safeScalars.contains($0) ? Character($0) : "-" })
    }

    /// The issue a `.dev/issue-N.json` file belongs to; nil for a branch's file or anything else.
    static func issueNumber(fileName: String) -> Int? {
        guard fileName.hasPrefix("issue-"), fileName.hasSuffix(".json") else { return nil }
        return Int(fileName.dropFirst("issue-".count).dropLast(".json".count))
    }

    /// The `docs/backlog/` entry a `.dev/local-ID.json` file belongs to (dev.py slugs the id; entry ids are already safe).
    static func localID(fileName: String) -> String? {
        guard fileName.hasPrefix("local-"), fileName.hasSuffix(".json") else { return nil }
        let id = String(fileName.dropFirst("local-".count).dropLast(".json".count))
        return id.isEmpty ? nil : id
    }

    static func parse(_ data: Data) -> PipelineState? {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let phase = object["phase"] as? Int else { return nil }
        return PipelineState(phase: phase, phaseGroup: object["phase_group"] as? String, tier: object["tier"] as? String,
                             phasesCompleted: object["phases_completed"] as? [Int] ?? [])
    }

    var progress: PipelineProgress {
        let stages = Self.stages.map { stage in
            PipelineStage(stage.name, phase > stage.phases.upperBound ? .done : stage.phases.contains(phase) ? .current : .pending)
        }
        return PipelineProgress(stages: stages, note: "Advisory — read from .dev state; git wins any disagreement.")
    }

    /// A checkpoint records the phase that CLEARED, so the card names the work after it: phase 4 done is Planning.
    var cardNote: String {
        let working = phase + 1
        let label = working <= 8 ? "Planning" : working <= 10 ? "Implementing" : working <= 13 ? "Verifying" : "Opening the PR"
        return "\(label) · phase \(phase) done"
    }

    var check: CheckResult {
        CheckResult(id: "pipeline", name: "Pipeline state", outcome: .passed,
                    outcomeLabel: "phase \(phase) · \(tier ?? "no tier")", revisionLabel: "advisory")
    }
}

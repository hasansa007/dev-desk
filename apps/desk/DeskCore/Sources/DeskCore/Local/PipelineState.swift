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

    var cardNote: String {
        ["Phase \(phase)", phaseGroup, "advisory"].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    var check: CheckResult {
        CheckResult(id: "pipeline", name: "Pipeline state", outcome: .passed,
                    outcomeLabel: "phase \(phase) · \(tier ?? "no tier")", revisionLabel: "advisory")
    }
}

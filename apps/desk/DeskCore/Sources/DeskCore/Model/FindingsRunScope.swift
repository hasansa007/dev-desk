/// Which half of its report a `dev:survey` run writes. It is the door's own `--bugs`/`--arch` argument, and
/// it is also the run's identity: two surveys in one repo are only a problem when they write the same half.
///
/// The cases live here rather than in the sheet that offers them because the rule below is the registry's to
/// hold — the app has to answer "may this start?" for a background job it does not own a view of.
public enum SurveyRunScope: String, CaseIterable, Hashable, Sendable {
    case both, defects, architecture

    /// What a run of this scope writes over. `both` occupies both halves, which is what makes it conflict
    /// with everything: a defects run beside it would write the defect half twice.
    private var halves: Set<String> {
        switch self {
        case .both: return ["defects", "architecture"]
        case .defects: return ["defects"]
        case .architecture: return ["architecture"]
        }
    }

    /// Two surveys may run side by side only when they share no half of the report. So the same scope twice
    /// is refused, `defects` and `architecture` run together, and `both` is refused beside either of them.
    public func conflicts(with other: SurveyRunScope) -> Bool {
        !halves.isDisjoint(with: other.halves)
    }

    /// What the run, its terminal row and its background job are called. A repo running two surveys at once
    /// needs two names, or both rows read "Survey" and neither says which half it is writing.
    public var runTitle: String {
        switch self {
        case .both: return "Survey"
        case .defects: return "Survey · Defects"
        case .architecture: return "Survey · Architecture"
        }
    }

    /// A run recorded without a scope predates this rule — or was started by a path that names no half, which
    /// means it may write either one. Reading it as `both` keeps that run blocking, rather than silently
    /// letting a second survey write over it.
    public init(recorded: String?) {
        self = recorded.flatMap(SurveyRunScope.init(rawValue:)) ?? .both
    }
}

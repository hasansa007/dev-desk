/// Builds git read invocations that a hostile repository can't turn into code execution.
enum GitCommand {
    /// Neutralises repo-controlled hooks, fsmonitor and external diff programs for the duration of one read.
    static let readFlags = ["-c", "core.fsmonitor=", "-c", "core.hooksPath=/dev/null", "-c", "diff.external="]

    /// The hardening flags, which must precede the subcommand, followed by it.
    static func read(_ arguments: [String]) -> [String] { readFlags + arguments }
}

/// Builds git read invocations that a hostile repository can't turn into code execution.
enum GitCommand {
    /// Neutralises repo-controlled programs a read could otherwise run: hooks, fsmonitor, external diff, and the signature verifiers.
    static let readFlags = [
        "-c", "core.fsmonitor=",
        "-c", "core.hooksPath=/dev/null",
        "-c", "diff.external=",
        "-c", "log.showSignature=false",
        "-c", "gpg.program=false",
        "-c", "gpg.ssh.program=false",
        "-c", "gpg.x509.program=false",
    ]

    /// The hardening flags, which must precede the subcommand, followed by it.
    static func read(_ arguments: [String]) -> [String] { readFlags + arguments }
}

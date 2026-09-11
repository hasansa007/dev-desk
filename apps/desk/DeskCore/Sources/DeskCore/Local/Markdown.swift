/// Escaping for repo-derived text that lands in a field the app renders as inline markdown.
enum Markdown {
    /// Backslash-escapes the characters inline markdown would otherwise treat as syntax, so attacker text renders literally.
    static func escape(_ text: String) -> String {
        var escaped = ""
        for character in text {
            if "\\`*_[]<>~&".contains(character) { escaped.append("\\") }
            escaped.append(character)
        }
        return escaped
    }

    /// A fragment of command output (git or gh stderr/stdout) made safe for a markdown-rendered reason.
    static func reason(_ commandOutput: String) -> String { escape(commandOutput) }
}

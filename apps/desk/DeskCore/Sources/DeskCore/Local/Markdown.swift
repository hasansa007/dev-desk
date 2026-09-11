/// Escaping for repo-derived text that lands in a field the app renders as inline markdown.
public enum Markdown {
    /// Backslash-escapes the characters inline markdown would otherwise treat as syntax, and breaks the autolinks bare URLs, `www.` hosts and emails would get, so attacker text renders literally and never as a link.
    public static func escape(_ text: String) -> String {
        let characters = Array(text)
        var escaped = ""
        for (index, character) in characters.enumerated() {
            switch character {
            case "@":
                // Email autolinking runs after escapes resolve, so the "@" gets a span of its own: an empty attribute span adds nothing, and unlike an empty link it leaves an enclosing link intact.
                escaped.append("^[@]()")
            case ":" where characters[(index + 1)...].starts(with: "//"):
                escaped.append("\\:")
            case "." where index >= 3 && String(characters[(index - 3)..<index]).lowercased() == "www":
                escaped.append("\\.")
            default:
                if "\\`*_[]<>~&".contains(character) { escaped.append("\\") }
                escaped.append(character)
            }
        }
        return escaped
    }

    /// A fragment of command output (git or gh stderr/stdout) made safe for a markdown-rendered reason.
    static func reason(_ commandOutput: String) -> String { escape(commandOutput) }
}

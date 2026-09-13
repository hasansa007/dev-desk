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

    /// Strips inline emphasis and code markers, for text that is drawn as plain text rather than rendered.
    /// A survey bullet bolds its claim, and a title shown with its own `**` around it reads as a typo.
    ///
    /// Only `*` and backticks go. Underscores stay: in this app's text they are far more often part of an
    /// identifier (`is_loading`) than a pair of emphasis markers, and silently eating them renames the thing
    /// the finding is about.
    public static func plain(_ text: String) -> String {
        var output = ""
        var characters = Array(text)[...]
        while let character = characters.first {
            if character == "\\", characters.count > 1, "\\`*_[]<>~&".contains(characters[characters.startIndex + 1]) {
                output.append(characters[characters.startIndex + 1])   // an escaped marker is a literal character
                characters = characters.dropFirst(2)
            } else if character == "*" || character == "`" {
                characters = characters.dropFirst()                    // the marker itself, however many there are
            } else {
                output.append(character)
                characters = characters.dropFirst()
            }
        }
        return output.trimmingCharacters(in: .whitespaces)
    }

    /// The exact inverse of `escape`, for text leaving the app as a file rather than being rendered in it.
    /// Written escaped, a backlog entry about `@ObservedObject` would read `^[@]()ObservedObject` to a person.
    public static func unescape(_ text: String) -> String {
        var output = text.replacingOccurrences(of: "^[@]()", with: "@")
        var result = ""
        var characters = Array(output)[...]
        while let character = characters.first {
            if character == "\\", characters.count > 1,
               "\\`*_[]<>~&:.".contains(characters[characters.startIndex + 1]) {
                result.append(characters[characters.startIndex + 1])
                characters = characters.dropFirst(2)
            } else {
                result.append(character)
                characters = characters.dropFirst()
            }
        }
        output = result
        return output
    }

    /// A fragment of command output (git or gh stderr/stdout) made safe for a markdown-rendered reason.
    static func reason(_ commandOutput: String) -> String { escape(commandOutput) }
}

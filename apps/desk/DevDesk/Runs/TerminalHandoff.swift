import AppKit
import DeskCore

/// Runs a command in the developer's OWN terminal, not one Dev Desk hosts (ADR 0036 §4.7).
///
/// Sign-in is the case this exists for. A device-code flow, a browser hand-off and a password prompt all
/// want a real terminal, and decision 14 — the app never touches a credential — is strongest when the app
/// does not even host the pty the credential flows through. It is also the mechanism *Continue in ▾* uses to
/// hand a session to Terminal, so it is written once here.
///
/// AppleScript needs Automation permission, which macOS asks for the first time and the person can refuse.
/// A refusal is not an error worth a dialog: the command goes to the clipboard and the caller says so, which
/// is a working answer with one more keystroke.
enum TerminalHandoff {
    enum Outcome: Equatable {
        case opened(app: String)
        /// Automation was refused or no terminal answered; the command is on the clipboard instead.
        case copied
    }

    /// iTerm when it is the default and installed, Terminal otherwise — a person who runs iTerm does not
    /// want a second terminal app opening behind it.
    static func run(_ command: String, in directory: URL?) -> Outcome {
        let script = appleScript(for: command, in: directory)
        for app in ["iTerm", "Terminal"] where isInstalled(app) {
            if runAppleScript(script(app)) { return .opened(app: app) }
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
        return .copied
    }

    private static func isInstalled(_ app: String) -> Bool {
        let ids = ["iTerm": "com.googlecode.iterm2", "Terminal": "com.apple.Terminal"]
        guard let id = ids[app] else { return false }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) != nil
    }

    /// `do script` opens a window and runs the line, which is what a sign-in wants: a prompt already waiting.
    private static func appleScript(for command: String, in directory: URL?) -> (String) -> String {
        let line = directory.map { "cd \(shellQuoted($0.path)) && \(command)" } ?? command
        return { app in
            """
            tell application "\(app)"
                activate
                do script "\(appleScriptQuoted(line))"
            end tell
            """
        }
    }

    private static func runAppleScript(_ source: String) -> Bool {
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        return error == nil
    }

    /// Single quotes have no escape inside them, so a quote is closed, escaped and reopened — the rule
    /// `DoorCommand.quoted` already uses, applied to a path this time.
    private static func shellQuoted(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// AppleScript string literals escape a backslash and a double quote, and nothing else.
    private static func appleScriptQuoted(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }
}

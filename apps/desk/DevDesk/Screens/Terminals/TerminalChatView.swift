import DeskCore
import SwiftTerm
import SwiftUI

/// A live terminal read as a conversation: what the shell has on its screen and in its scrollback, cut into
/// turns, with the composer under it typing into the same shell. It is a reading of the terminal, not a second
/// host of it (ADR 0026): the registry's view is asked for its text and sent the input, and never re-parented
/// here — the Terminal view of the same row is the only place it is drawn.
///
/// Best effort, and said to be. A terminal has no idea of turns; the text is split where a prompt line or a
/// blank line falls (`TerminalTurns`), and a full-screen CLI keeps no scrollback at all, so what is read
/// is whatever it is showing now. When the split finds nothing to call a turn, the text is shown as one
/// read-only transcript rather than as bubbles that would claim more than they know.
struct TerminalChatView: View {
    let model: ProjectWindowModel
    let terminals: ShellTerminalRegistry
    let id: String
    @AppStorage(PreferenceKey.chatStyle) private var chatStyle = ChatStyle.bubbles
    @State private var text = ""
    @State private var draft = ""
    @State private var modelName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            transcript
            ChatComposer(model: model, draft: $draft, modelName: $modelName,
                         placeholder: "Type into the shell…", showsRunControls: false) { line in
                terminals.send(line + "\n", to: id)
            }
            Text("A reading of the terminal's own text, split into turns where a prompt or a blank line falls. Sent text is typed into the shell as if at its prompt.")
                .font(.system(size: 11))
                .foregroundStyle(DeskColor.faintInk)
                .lineSpacing(3)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(DeskColor.canvas)
        .task(id: id) { await follow() }
    }

    /// The registry's terminal is asked for its text on a short clock while this view is on screen; the delegate
    /// that would say when it changed belongs to the registry, and is left as it is. Nothing is redrawn unless
    /// the text differs.
    private func follow() async {
        while !Task.isCancelled {
            let latest = TerminalTurns.text(of: terminals.view(for: id))
            if latest != text { text = latest }
            try? await Task.sleep(for: .milliseconds(600))
        }
    }

    private var blocks: [TerminalTurns.Block] { TerminalTurns.blocks(in: text) }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: chatStyle == .bubbles ? 10 : 6) {
                    if blocks.isEmpty {
                        Text(text.isEmpty ? "The shell has written nothing yet." : "Nothing here reads as a turn yet; the Terminal view shows the screen as it is.")
                            .font(DeskFont.body)
                            .foregroundStyle(DeskColor.mutedInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(blocks) { block in
                        Group {
                            switch chatStyle {
                            case .bubbles: bubble(block)
                            case .transcript: line(block)
                            }
                        }
                        .id(block.id)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onChange(of: blocks.count) { _, _ in
                withAnimation { proxy.scrollTo(blocks.last?.id, anchor: .bottom) }
            }
        }
    }

    /// The chat's own shapes: yours on the right in the accent's tint, the shell's on the left on the surface —
    /// but the shell's text stays monospaced and verbatim, since it is a screen, not prose.
    private func bubble(_ block: TerminalTurns.Block) -> some View {
        let isUser = block.role == .user
        let tone = DeskColor.tone(.info)
        let shape = RoundedRectangle(cornerRadius: 9)
        return HStack(spacing: 0) {
            if isUser { Spacer(minLength: 60) }
            Text(verbatim: block.text)
                .font(isUser ? DeskFont.body : DeskFont.mono(12))
                .foregroundStyle(DeskColor.ink)
                .lineSpacing(3)
                .textSelection(.enabled)
                .frame(alignment: .leading)
                .padding(10)
                .background(isUser ? tone.fill : DeskColor.surface, in: shape)
                .overlay(shape.strokeBorder(isUser ? tone.border : DeskColor.border))
            if !isUser { Spacer(minLength: 60) }
        }
    }

    private func line(_ block: TerminalTurns.Block) -> some View {
        let isUser = block.role == .user
        return HStack(alignment: .top, spacing: 8) {
            Text(isUser ? "you>" : "shell>")
                .font(DeskFont.mono(12, weight: .semibold))
                .foregroundStyle(isUser ? DeskColor.accent : DeskColor.tone(.running).foreground)
            Text(verbatim: block.text)
                .font(DeskFont.mono(12))
                .foregroundStyle(DeskColor.ink)
                .lineSpacing(3)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Reads a terminal's text and cuts it into turns. Pure functions on strings past the first, so the cut can be
/// tested without a terminal.
enum TerminalTurns {
    struct Block: Identifiable, Hashable {
        enum Role: Hashable { case user, shell }
        /// The block's place in the text: stable while the text above it does not change, which keeps the
        /// list still as new output arrives below.
        let id: Int
        let role: Role
        let text: String
    }

    /// Everything the terminal retains, scrollback and screen, as SwiftTerm's own selection would copy it:
    /// soft-wrapped rows joined back into one line, and the blank rows below the cursor dropped. The end row is
    /// clamped inside SwiftTerm to the last line held, and the line count is not public, so the largest row is
    /// asked for. Cells are what the emulator drew, so escape sequences are already interpreted; anything that
    /// still reads as a control character is dropped in `blocks`.
    @MainActor
    static func text(of view: LocalProcessTerminalView) -> String {
        let terminal = view.getTerminal()
        return terminal.getText(start: Position(col: 0, row: 0), end: Position(col: terminal.cols, row: Int(Int32.max)))
    }

    /// A line the user typed at: a prompt of up to sixty characters ending in `$`, `%`, `#` or `❯` — zsh's
    /// `user@host dir %` has a space in it, so spaces are allowed — or a line starting with the `>`/`›` an
    /// agent CLI echoes a message under, then one space and the text. A digit before the marker is ruled out,
    /// so "50% done" is output; `#` alone at the start is ruled out, so a markdown heading is too. A `>` that
    /// starts a quoted line, or a "$ 5" mid-sentence, will still be mistaken for a turn, which is the price
    /// of reading a screen that never said who wrote what.
    private static let prompt = try! NSRegularExpression(pattern: #"^(?:\S.{0,58}?(?<!\d)[$%#❯]|[$%❯>›])\s(\S.*)$"#)

    /// The same prompt with nothing typed after it: the shell waiting, which is not a turn of anyone's.
    private static let barePrompt = try! NSRegularExpression(pattern: #"^(?:\S.{0,58}?(?<!\d)[$%#❯]|[$%❯>›])\s*$"#)

    /// Whatever the emulator left uninterpreted: ANSI CSI and OSC sequences, lone escapes, and the C0 controls
    /// other than tab and newline.
    private static let controls = try! NSRegularExpression(
        pattern: #"\x{1b}\[[0-?]*[ -/]*[@-~]|\x{1b}\][^\x{07}\x{1b}]*(?:\x{07}|\x{1b}\\)|\x{1b}[@-Z\\-_]|[\x{00}-\x{08}\x{0b}-\x{1f}\x{7f}]"#)

    /// The cut: a prompt line with a command is a turn of the user's, holding the command alone; the lines that
    /// follow, up to the next blank line or prompt, are the shell's; a run of blank lines, or a bare prompt,
    /// ends a block. Consecutive shell blocks stay separate, since a blank line between them is where the
    /// output paused.
    static func blocks(in raw: String) -> [Block] {
        let clean = controls.stringByReplacingMatches(in: raw, range: NSRange(raw.startIndex..., in: raw), withTemplate: "")
        var blocks: [Block] = []
        var current: [String] = []
        func flush() {
            let text = current.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { blocks.append(Block(id: blocks.count, role: .shell, text: text)) }
            current = []
        }
        for line in clean.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            if line.trimmingCharacters(in: .whitespaces).isEmpty || isBarePrompt(line) {
                flush()
            } else if let command = typedCommand(in: line) {
                flush()
                blocks.append(Block(id: blocks.count, role: .user, text: command))
            } else {
                current.append(line)
            }
        }
        flush()
        return blocks
    }

    /// The text after the prompt when `line` reads as one, else nil.
    static func typedCommand(in line: String) -> String? {
        let range = NSRange(line.startIndex..., in: line)
        guard let match = prompt.firstMatch(in: line, range: range),
              let command = Range(match.range(at: 1), in: line) else { return nil }
        return String(line[command]).trimmingCharacters(in: .whitespaces)
    }

    static func isBarePrompt(_ line: String) -> Bool {
        barePrompt.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil
    }
}

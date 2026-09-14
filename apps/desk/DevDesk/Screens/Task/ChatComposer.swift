import AppKit
import DeskCore
import SwiftUI

/// Where a message to an agent is written, wherever one is written: a chat session's body, the Sessions
/// screen's own "start by typing" entry, and the Chat view of a live terminal. One composer, so the chips, the
/// attach button and the send button are the same in each place, and a change to what they do is made once.
///
/// The chips are the app's defaults, not this composer's: the mode, the connection and the chat style write the
/// same preferences Settings writes, so choosing here changes what the next task start would run too, and the
/// transcript redraws at once. The model chip is a curated per-agent list the CLI reads as `--model`: the tools
/// cannot list what they support, so Dev Desk carries a small convenience set plus Default and a Custom
/// escape hatch. Attaching a file inserts an `@path` mention into the text and nothing more: nothing is
/// uploaded and nothing is kept, and the message still runs through the login shell as ever (decision 14).
///
/// The draft and the model name are the caller's, so a row that collapses and a screen that is left both keep
/// what was being typed. The caller also says what the message does when it is sent: this view never runs one.
struct ChatComposer: View {
    let model: ProjectWindowModel
    @Binding var draft: String
    @Binding var modelName: String
    /// Why nothing can be sent right now — no agent, no folder, a shell that has ended — or nil when it can.
    /// It disables the input, and reads as the send button's help.
    var blockedReason: String?
    /// True while an answer is on its way. The text stays editable, so the next message can be written while
    /// this one is answered, but nothing is sent until the answer is in.
    var isSending = false
    var placeholder = "Ask the agent about this project…"
    /// Whether the run controls — mode, connection, model — are shown. A live shell is already running whatever
    /// it runs, so a composer that types into one shows only the folder it types in.
    var showsRunControls = true
    let onSend: (String) -> Void

    @AppStorage(PreferenceKey.runMode) private var runMode = AgentDefaults.runMode
    @AppStorage(PreferenceKey.defaultConnection) private var defaultConnection = AgentDefaults.connection
    @AppStorage(PreferenceKey.chatStyle) private var chatStyle = ChatStyle.bubbles

    /// True while the Custom model field is shown: chosen from the menu, or forced open on appear because the
    /// current model name is one the curated list does not carry, so a custom name is not hidden behind a menu.
    @State private var showingCustomModel = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            chips
                .padding(.horizontal, 10)
                .padding(.top, 9)
            TextField(placeholder, text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(DeskFont.body)
                .lineLimit(2...8)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .onSubmit(send)
                .disabled(blockedReason != nil)
            controls
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
        }
        .background(DeskColor.surface, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(DeskColor.controlBorder))
    }

    // MARK: - What it runs, and where

    private var canSend: Bool {
        blockedReason == nil && !isSending && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The connections this Mac has, by the names Settings lists them under. The stored default is kept in the
    /// list even when the snapshot has not named it yet, so the chip never shows a choice the menu lacks.
    private var connections: [String] {
        let providers = model.snapshot?.capabilities.providers ?? []
        return providers.contains(defaultConnection) ? providers : providers + [defaultConnection]
    }

    private var projectName: String { model.snapshot?.project.name ?? model.ref.displayName }

    /// The folder, then the mode, the connection and the chat style — what a message runs under and how the
    /// conversation reads, left to right.
    private var chips: some View {
        HStack(spacing: 6) {
            ComposerChip(icon: "folder", text: projectName)
                .help(model.projectRoot?.path ?? "A sample has no folder.")
            if showsRunControls {
                Menu {
                    Picker("Mode", selection: $runMode) {
                        ForEach(RunMode.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.inline)
                } label: {
                    ComposerChip(icon: "arrow.triangle.branch", text: runMode.title, isMenu: true)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("The app's default mode. \(runMode.detail)")
                .accessibilityLabel("Mode")
                Menu {
                    Picker("Connection", selection: $defaultConnection) {
                        ForEach(connections, id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.inline)
                } label: {
                    ComposerChip(icon: "sparkles", text: defaultConnection, isMenu: true)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("The app's default connection, which answers here and starts every task")
                .accessibilityLabel("Connection")
                Menu {
                    Picker("Chat style", selection: $chatStyle) {
                        ForEach(ChatStyle.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.inline)
                } label: {
                    ComposerChip(icon: "bubble.left.and.bubble.right", text: chatStyle.title, isMenu: true)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("How the conversation reads — bubbles or a plain transcript. Applies everywhere at once.")
                .accessibilityLabel("Chat style")
            }
            Spacer(minLength: 0)
        }
    }

    /// The agent the model list is for: whatever the chosen connection resolves to, or nil when it is not one
    /// Dev Desk drives (Gemini, or a name no tool claims), which leaves only Default and Custom.
    private var selectedAgent: AgentKind? { AgentLaunch.agent(forConnectionName: defaultConnection) }

    /// The curated names for the current agent; empty when there is no known agent to curate for.
    private var curatedModels: [String] { selectedAgent.map(ModelCatalog.models(for:)) ?? [] }

    /// Whether the current name is a custom one — non-empty and outside the curated list — so the menu marks
    /// Custom selected and the inline field stays open with it.
    private var isCustomModel: Bool { !modelName.isEmpty && !curatedModels.contains(modelName) }

    /// The chip label: "Default" for an empty name, else the model string itself, truncated to one line.
    private var modelLabel: String { modelName.isEmpty ? "Default" : modelName }

    /// Attach on the left, the model in the middle, send on the right: what the message carries, what it runs
    /// as, and the button that sends it.
    private var controls: some View {
        HStack(spacing: 8) {
            Button(action: attach) {
                Image(systemName: "paperclip")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(DeskColor.secondaryInk)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(blockedReason != nil)
            .help("Mention files in the message as @path. Nothing is uploaded.")
            .accessibilityLabel("Attach files")
            if showsRunControls {
                modelMenu
                if showingCustomModel {
                    TextField("a model name the tool understands", text: $modelName)
                        .textFieldStyle(.plain)
                        .font(DeskFont.body)
                        .padding(.horizontal, 10)
                        .frame(width: 180, height: DeskMetric.controlHeight)
                        .background(DeskColor.canvas, in: RoundedRectangle(cornerRadius: DeskMetric.controlRadius))
                        .overlay(RoundedRectangle(cornerRadius: DeskMetric.controlRadius).strokeBorder(DeskColor.controlBorder))
                        .disabled(blockedReason != nil)
                        .help("Passed to the CLI as --model. Empty runs the tool's own default.")
                }
            }
            Spacer(minLength: 0)
            Button(action: send) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(canSend ? DeskColor.accent : DeskColor.disabledDot, in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(!canSend)
            .help(blockedReason ?? "Send (⌘↩)")
            .accessibilityLabel("Send")
        }
    }

    /// A /model-style picker, not a text box: Default, then the curated names for the chosen agent, then a
    /// Custom item that reveals an inline field. The tools cannot list their own models, so the list is Dev
    /// Desk's own, and Custom is the escape hatch for anything it does not carry. A checkmark marks whichever
    /// of Default, a curated name, or Custom the current `modelName` reads as.
    private var modelMenu: some View {
        Menu {
            Button { chooseDefault() } label: {
                Label("Default", systemImage: modelName.isEmpty ? "checkmark" : "")
            }
            if !curatedModels.isEmpty {
                Divider()
                ForEach(curatedModels, id: \.self) { name in
                    Button { choose(name) } label: {
                        Label(name, systemImage: modelName == name ? "checkmark" : "")
                    }
                }
            }
            Divider()
            Button { chooseCustom() } label: {
                Label("Custom…", systemImage: isCustomModel ? "checkmark" : "")
            }
        } label: {
            ComposerChip(icon: "cpu", text: modelLabel, isMenu: true)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(blockedReason != nil)
        .help("The model passed to the CLI as --model. Default runs the tool's own.")
        .accessibilityLabel("Model")
        // A custom name that arrives from the caller (a restored draft) opens the field pre-filled, so it is
        // never hidden behind the menu.
        .onAppear { if isCustomModel { showingCustomModel = true } }
    }

    /// Default → empty name (callers map empty → nil → the tool's own default), and the custom field closes.
    private func chooseDefault() {
        modelName = ""
        showingCustomModel = false
    }

    /// A curated name sets it exactly, and closes the custom field.
    private func choose(_ name: String) {
        modelName = name
        showingCustomModel = false
    }

    /// Custom reveals the inline field. A curated name in the box is cleared first, so the field opens ready
    /// for a name to be typed rather than showing a curated one as if it were custom.
    private func chooseCustom() {
        if !isCustomModel { modelName = "" }
        showingCustomModel = true
    }

    // MARK: - Sending and attaching

    private func send() {
        guard canSend else { return }
        let text = draft
        draft = ""
        onSend(text)
    }

    /// Each chosen file becomes an `@path` mention in the text, where the caret would have put it: relative
    /// to the project root when it is inside the project, which is how the CLIs read a mention, else absolute.
    private func attach() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.directoryURL = model.projectRoot
        panel.message = "Each chosen file is mentioned in the message as @path. Nothing is uploaded or stored."
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        let mentions = panel.urls.map { "@" + Self.mention(for: $0, root: model.projectRoot) }.joined(separator: " ")
        let needsSpace = !(draft.isEmpty || draft.last?.isWhitespace == true)
        draft += (needsSpace ? " " : "") + mentions + " "
    }

    /// The path a mention names: relative under `root`, absolute anywhere else. Both are standardized first, so
    /// a symlinked or `..`-laden choice inside the project still reads as inside it.
    static func mention(for url: URL, root: URL?) -> String {
        let path = url.standardizedFileURL.path
        guard let root else { return path }
        let rootPath = root.standardizedFileURL.path
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        return path.hasPrefix(prefix) ? String(path.dropFirst(prefix.count)) : path
    }
}

/// A chip in the composer: an icon, a word, and a chevron when it opens a menu. The same pill the findings
/// screen uses to choose a run, so a chip that opens a menu looks like one everywhere.
private struct ComposerChip: View {
    let icon: String
    let text: String
    var isMenu = false

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(DeskColor.mutedInk)
            Text(text)
                .font(DeskFont.secondary)
                .foregroundStyle(DeskColor.secondaryInk)
                .lineLimit(1)
            if isMenu {
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(DeskColor.mutedInk)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(DeskColor.canvas, in: RoundedRectangle(cornerRadius: DeskMetric.pillRadius))
        .overlay(RoundedRectangle(cornerRadius: DeskMetric.pillRadius).strokeBorder(DeskColor.border))
        .fixedSize()
    }
}

import AVFoundation
import Speech
import SwiftUI

/// Dictation the app runs itself: the recognizer behind the strip's mic and ⇧⌘D (`Dictation`).
///
/// macOS has its own dictation and it reaches the terminal too now — SwiftTerm was dropping the attributed string
/// the system commits, which `FocusingTerminalView.insertText` unwraps. This is the other half, and the half that
/// is visible: a button that is plainly there, that types into *this* session rather than wherever the caret
/// happens to be, and that never presses Return. What was heard lands at the agent's prompt for the user to read
/// and correct before sending it.
///
/// Recognition is on the device wherever the Mac can do it, so nothing said into a developer's terminal leaves it.
@MainActor
@Observable
final class VoiceDictation {
    enum Status: Equatable {
        case off
        /// Waiting on the two permission prompts, which appear only the first time.
        case asking
        case listening
        /// Shown next to the mic until the next press; the mic itself is back off.
        case problem(String)
    }

    private(set) var status: Status = .off
    /// What has been heard so far, as the recognizer keeps revising it. Empty until the first phrase.
    private(set) var heard = ""

    var isListening: Bool { status == .listening }

    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private var request: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var task: SFSpeechRecognitionTask?
    @ObservationIgnored private var type: ((String) -> Void)?

    /// The button: start listening, or stop and type what was heard.
    func toggle(typing type: @escaping (String) -> Void) {
        switch status {
        case .listening: finish()
        case .asking: cancel()
        case .off, .problem: begin(typing: type)
        }
    }

    private func begin(typing type: @escaping (String) -> Void) {
        self.type = type
        heard = ""
        status = .asking
        Task {
            guard await Self.permitted() else {
                status = .problem("Allow Dev Desk the microphone and speech recognition in System Settings › Privacy & Security.")
                return
            }
            guard case .asking = status else { return }
            listen()
        }
    }

    /// Both prompts, in the order they are needed: the recognizer first, since a refusal there makes the mic pointless.
    private static func permitted() async -> Bool {
        let speech = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard speech == .authorized else { return false }
        return await AVCaptureDevice.requestAccess(for: .audio)
    }

    private func listen() {
        guard let recognizer = SFSpeechRecognizer(locale: .current) ?? SFSpeechRecognizer(), recognizer.isAvailable else {
            status = .problem("No speech recognizer for \(Locale.current.identifier).")
            return
        }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        self.request = request
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        // A Mac with no input device gives a format of 0 channels at 0 Hz, and installing a tap on that traps.
        guard format.sampleRate > 0, format.channelCount > 0 else {
            self.request = nil
            status = .problem("No microphone is available.")
            return
        }
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in request.append(buffer) }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            teardown()
            status = .problem(error.localizedDescription)
            return
        }
        status = .listening
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            // The recognizer answers on a queue of its own.
            DispatchQueue.main.async {
                guard let self else { return }
                if let result { self.heard = result.bestTranscription.formattedString }
                guard error != nil || result?.isFinal == true else { return }
                // A recognizer that stopped on its own still owes the user the words it already has.
                if case .listening = self.status, self.heard.isEmpty, let error {
                    self.teardown()
                    self.status = .problem(error.localizedDescription)
                } else {
                    self.finish()
                }
            }
        }
    }

    /// Stops the mic and types what was heard. Idempotent on purpose: the button and the recognizer's own final
    /// result both land here, and whichever arrives second must type nothing twice.
    private func finish() {
        guard case .listening = status else { return }
        status = .off
        teardown()
        let text = heard.trimmingCharacters(in: .whitespacesAndNewlines)
        heard = ""
        if !text.isEmpty { type?(text + " ") }
        type = nil
    }

    /// The second press: types what was heard, or drops the start while the permission prompts are still up.
    func stop() {
        if case .listening = status { finish() } else { cancel() }
    }

    /// Stops without typing — the pane going away, or a press while the prompts are still up.
    func cancel() {
        guard status != .off else { return }
        status = .off
        heard = ""
        type = nil
        teardown()
    }

    private func teardown() {
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        request = nil
        task?.cancel()
        task = nil
    }
}

/// The app's one mic — the strip's button and ⇧⌘D. It was a button over every terminal, which put a mic in front of
/// each session but none within reach of the keyboard; now there is one, and it types into the session in front:
/// the terminal that last took the keys in the project on screen, else the one its Sessions tab has selected.
@MainActor
@Observable
final class Dictation {
    static let shared = Dictation()

    struct Target: Equatable {
        weak var registry: ShellTerminalRegistry?
        let sessionID: String

        static func == (lhs: Target, rhs: Target) -> Bool {
            lhs.sessionID == rhs.sessionID && lhs.registry === rhs.registry
        }
    }

    let voice = VoiceDictation()
    /// The terminal that last took the keys, in whichever project.
    private(set) var focused: Target?
    /// Where the words go, fixed at the press: switching projects mid-sentence still types where you began.
    private(set) var target: Target?

    var isBusy: Bool { voice.status == .listening || voice.status == .asking }

    func noteFocus(_ registry: ShellTerminalRegistry, _ sessionID: String) {
        focused = Target(registry: registry, sessionID: sessionID)
    }

    /// The session a press would type into in `context`; nil on Home, or when nothing there is running.
    /// Read from the sessions' state rather than the registry, so the strip's button dims the moment one ends.
    func candidate(in context: ProjectContext?) -> Target? {
        guard let context else { return nil }
        let isLive = { (id: String) in context.model.sessions.state(for: id).isLive }
        if let focused, focused.registry === context.terminals, isLive(focused.sessionID) { return focused }
        if let id = context.model.selectedSessionID, isLive(id) { return Target(registry: context.terminals, sessionID: id) }
        return nil
    }

    /// A press: starts listening for the session in front, or stops and types what was heard.
    func toggle(in context: ProjectContext?) {
        if isBusy { voice.stop(); return }
        guard let candidate = candidate(in: context), let registry = candidate.registry else { return }
        target = candidate
        let id = candidate.sessionID
        voice.toggle { [weak registry] text in registry?.send(text, to: id) }
    }
}

/// What the mic is hearing, over the session it types into — where your eyes already are. Nothing when this
/// session is not the target or the mic is off.
struct DictationNote: View {
    let registry: ShellTerminalRegistry
    let sessionID: String

    var body: some View {
        if let note {
            Text(verbatim: note)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(DeskColor.terminalDim2)
                .lineLimit(2)
                .multilineTextAlignment(.trailing)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(DeskColor.terminalControlFill, in: RoundedRectangle(cornerRadius: DeskMetric.controlRadius))
                .frame(maxWidth: 360, alignment: .trailing)
                // Clear of the terminal's scroller and its last row.
                .padding(.trailing, 32)
                .padding(.bottom, 28)
        }
    }

    private var note: String? {
        let dictation = Dictation.shared
        guard let target = dictation.target, target.sessionID == sessionID, target.registry === registry else { return nil }
        switch dictation.voice.status {
        case .off: return nil
        case .asking: return "Waiting for permission…"
        case .listening: return dictation.voice.heard.isEmpty ? "Listening…" : dictation.voice.heard
        case .problem(let reason): return reason
        }
    }
}

import AVFoundation
import Speech
import SwiftUI

/// Dictation the app runs itself: the mic button over a session's terminal.
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

/// The mic over a running session, with what it is hearing beside it. Its own state, so each pane dictates into
/// its own terminal and closing one stops only that mic.
struct VoiceButton: View {
    /// Types the finished text into the session — never sends it.
    let type: (String) -> Void

    @State private var voice = VoiceDictation()

    var body: some View {
        HStack(spacing: 8) {
            if let note {
                Text(verbatim: note)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(DeskColor.terminalDim2)
                    .lineLimit(2)
                    .frame(maxWidth: 320, alignment: .trailing)
                    .multilineTextAlignment(.trailing)
            }
            Button {
                voice.toggle(typing: type)
            } label: {
                Image(systemName: voice.isListening ? "mic.fill" : "mic")
                    .font(.system(size: 12))
                    .foregroundStyle(voice.isListening ? DeskColor.onColorInk : DeskColor.terminalInk)
                    .frame(width: 26, height: 26)
                    .background(voice.isListening ? DeskColor.accent : DeskColor.terminalControlFill, in: Circle())
                    .overlay(Circle().strokeBorder(DeskColor.terminalControlBorder))
            }
            .buttonStyle(.plain)
            .help(voice.isListening ? "Stop dictating and type what was heard" : "Dictate into this session")
            .accessibilityLabel(voice.isListening ? "Stop dictating" : "Dictate")
        }
        .padding(10)
        .onDisappear { voice.cancel() }
    }

    /// What to show beside the mic: the live text while it listens, or why it stopped.
    private var note: String? {
        switch voice.status {
        case .off: return nil
        case .asking: return "Waiting for permission…"
        case .listening: return voice.heard.isEmpty ? "Listening…" : voice.heard
        case .problem(let reason): return reason
        }
    }
}

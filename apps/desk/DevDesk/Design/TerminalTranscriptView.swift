import DeskCore
import SwiftUI

struct TerminalTranscriptView: View {
    let transcript: TerminalTranscript
    @AppStorage(PreferenceKey.terminalFontSize) private var fontSize = 12.0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                Text(styledLines)
                    .lineSpacing(fontSize * 0.45)
                    .textSelection(.enabled)
                if transcript.showsPrompt && !transcript.isReadOnly {
                    HStack(spacing: 6) {
                        Text("❯").foregroundStyle(DeskColor.terminalOK)
                        Rectangle()
                            .fill(DeskColor.terminalInk)
                            .frame(width: 7, height: 15)
                            .modifier(Pulse(period: 1.1))
                    }
                    .accessibilityHidden(true)
                }
            }
            .font(DeskFont.mono(fontSize))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
        }
        .background(DeskColor.terminalGround)
    }

    private var styledLines: AttributedString {
        let rows = [(transcript.header, DeskColor.terminalDim)] + transcript.lines.map { ($0.text, color(for: $0.kind)) }
        var text = AttributedString()
        for (line, color) in rows {
            var piece = AttributedString(text.characters.isEmpty ? line : "\n" + line)
            piece.foregroundColor = color
            text += piece
        }
        return text
    }

    private func color(for kind: TerminalLine.Kind) -> Color {
        switch kind {
        case .plain: return DeskColor.terminalInk
        case .success: return DeskColor.terminalOK
        case .failure: return DeskColor.terminalError
        case .dim: return DeskColor.terminalDim2
        }
    }
}

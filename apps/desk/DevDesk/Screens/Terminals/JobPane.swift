import DeskCore
import SwiftUI

/// A background run's pane: it has no terminal, so what it says is its log, and what it needs is an answer.
/// Without this the whole background feature (ADR 0025) was invisible — a run started, worked, failed or asked
/// a question, and nothing on screen ever mentioned it.
struct JobPane: View {
    let job: BackgroundJob
    @Binding var answer: String
    let send: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            log
            if let usage = job.usage { meter(usage) }
            if case .asking(let question) = job.state {
                asking(question)
            } else if case .ended(let text, let failed) = job.state, failed {
                NoticeBanner(tone: .failed, title: "The run ended with an error", message: text, style: .compact)
                    .padding(EdgeInsets(top: 0, leading: 11, bottom: 11, trailing: 11))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var log: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 3) {
                    if job.log.isEmpty {
                        Text(job.state.isLive ? "Waiting for its first line…" : "This run wrote nothing.")
                            .font(DeskFont.mono(11))
                            .foregroundStyle(DeskColor.faintInk)
                    }
                    ForEach(Array(job.log.enumerated()), id: \.offset) { index, line in
                        Text(line)
                            .font(DeskFont.mono(11))
                            .foregroundStyle(line.hasPrefix("› ") ? DeskColor.accent : DeskColor.secondaryInk)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(index)
                    }
                }
                .padding(11)
            }
            .onChange(of: job.log.count) { _, count in
                withAnimation { proxy.scrollTo(count - 1, anchor: .bottom) }
            }
        }
    }

    /// How much of its context the run is holding, from the agent's own numbers. It sits under the log, where
    /// the run's state is read, and it is deliberately quiet: this is a status line, not a dashboard. A run
    /// whose agent has reported nothing shows nothing at all, rather than a zero it has not measured.
    private func meter(_ usage: ContextUsage) -> some View {
        Text(usage.label)
            .font(DeskFont.mono(11))
            .foregroundStyle(DeskColor.faintInk)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(EdgeInsets(top: 0, leading: 11, bottom: 9, trailing: 11))
    }

    /// A headless run cannot prompt, so it stops and asks here; answering resumes the same session (ADR 0025).
    private func asking(_ question: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(question)
                .font(DeskFont.body)
                .foregroundStyle(DeskColor.ink)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                TextField("Your answer", text: $answer)
                    .textFieldStyle(.plain)
                    .font(DeskFont.body)
                    .padding(.horizontal, 10)
                    .controlChrome(height: 28)
                    .onSubmit(reply)
                Button("Send", action: reply)
                    .buttonStyle(DeskButtonStyle(kind: .primary, size: .small))
                    .disabled(answer.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(11)
        .background(DeskColor.headerFill)
        .overlay(alignment: .top) { Rectangle().fill(DeskColor.divider).frame(height: 1) }
    }

    private func reply() {
        let text = answer.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        send(text)
        answer = ""
    }
}

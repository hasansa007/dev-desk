import DeskCore
import SwiftUI

struct ActivityTab: View {
    let model: ProjectWindowModel
    let task: DeskTask

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let notice = task.notice {
                TaskNoticeView(model: model, notice: notice, offersHandoff: task.handoff != nil)
                    .padding(.bottom, 16)
            }
            if let pipeline = task.pipeline {
                TaskPipelineRow(pipeline: pipeline)
                    .padding(.bottom, 14)
            }
            SurfaceView(task.activity) { events in
                if events.isEmpty {
                    // Activity is the branch's commits, so an unstarted task has none rather than nothing to say.
                    Text(task.branch == nil
                         ? "No commits yet — this task has no branch. Its commits appear here once its run starts committing."
                         : "No commits on \(task.branch ?? "") yet.")
                        .font(DeskFont.body)
                        .foregroundStyle(DeskColor.mutedInk)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(events) { event in
                            ActivityEventRow(event: event, onFollowUp: event.offersFollowUp ? { model.present(.followUp) } : nil)
                        }
                    }
                    .frame(maxWidth: 860, alignment: .leading)
                }
            }
            if task.canCompareOutputs {
                Button("Compare two agent outputs…") { model.present(.compareOutputs) }
                    .buttonStyle(DeskButtonStyle(kind: .secondary))
                    .fixedSize()
                    .padding(.top, 16)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct TaskPipelineRow: View {
    let pipeline: PipelineProgress

    var body: some View {
        HStack(spacing: 10) {
            SectionLabel("Pipeline")
            HStack(spacing: 6) {
                ForEach(Array(pipeline.stages.enumerated()), id: \.offset) { index, stage in
                    if index > 0 {
                        Text(verbatim: "›")
                            .font(DeskFont.secondary)
                            .foregroundStyle(DeskColor.disabledDot)
                            .accessibilityHidden(true)
                    }
                    TaskPipelineStageChip(stage: stage)
                }
            }
            if let note = pipeline.note {
                Text(note)
                    .font(.system(size: 11))
                    .foregroundStyle(DeskColor.faintInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct TaskPipelineStageChip: View {
    let stage: PipelineStage

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DeskMetric.pillRadius)
        let colors = self.colors
        Text(stage.name)
            .font(.system(size: 12, weight: stage.state == .current ? .semibold : .regular))
            .foregroundStyle(colors.foreground)
            .padding(.vertical, 3)
            .padding(.horizontal, 9)
            .background(colors.fill, in: shape)
            .overlay(shape.strokeBorder(colors.border))
            .fixedSize()
            .accessibilityLabel("\(stage.name), \(stage.state.rawValue)")
    }

    private var colors: (foreground: Color, fill: Color, border: Color) {
        switch stage.state {
        case .done:
            let tone = DeskColor.tone(.running)
            return (tone.foreground, tone.fill, tone.border)
        case .current:
            let tone = DeskColor.tone(.info)
            return (tone.foreground, tone.fill, tone.border)
        case .pending:
            return (DeskColor.faintInk, DeskColor.neutralChipFill2, DeskColor.border)
        }
    }
}

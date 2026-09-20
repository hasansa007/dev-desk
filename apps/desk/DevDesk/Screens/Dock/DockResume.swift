import DeskCore
import SwiftUI

/// Something the + offers to continue rather than to start: a run the app died under (ADR 0031), or a task
/// whose branch is on disk and whose session is not. Every one of these is a decision the developer makes —
/// nothing here is resumed because the dock was opened.
struct ResumeOffer: Identifiable {
    let id: String
    let title: String
    /// What it was and how far it got, in the one line a menu row can carry.
    let subtitle: String
    let tone: StatusTone
    let run: () -> Void
}

/// Builds the + menu's Resume half. It drives the recovery that already exists — `RunJournal.recover()`,
/// `JobRegistry.resumeFromRecord`, `AgentResume` — rather than keeping a second record of its own, because
/// the app still keeps no transcript: a resume is either that CLI's own resume in the same worktree, or the
/// honest second best of a fresh shell where the work was left.
@MainActor
enum DockResume {
    static func offers(model: ProjectWindowModel, jobs: JobRegistry?, terminals: ShellTerminalRegistry?,
                       worktreeLocation: String, show: @escaping (String) -> Void,
                       reload: @escaping () -> Void) -> [ResumeOffer] {
        recovered(model: model, jobs: jobs, terminals: terminals, worktreeLocation: worktreeLocation,
                  show: show, reload: reload)
            + paused(model: model, terminals: terminals, worktreeLocation: worktreeLocation, show: show)
    }

    /// What was live when Dev Desk last closed unexpectedly. A record whose run is live in this app is not a
    /// recovery — it is a chip in the bar already.
    private static func recovered(model: ProjectWindowModel, jobs: JobRegistry?,
                                  terminals: ShellTerminalRegistry?, worktreeLocation: String,
                                  show: @escaping (String) -> Void,
                                  reload: @escaping () -> Void) -> [ResumeOffer] {
        guard let journal = model.sessions.journal else { return [] }
        let records = journal.recover().filter {
            jobs?.job($0.id) == nil && !model.sessions.runningTaskIDs.contains($0.id)
        }
        return records.compactMap { record -> ResumeOffer? in
            let done = { journal.clear(id: record.id); reload() }
            switch record.kind {
            case .backgroundRun:
                // Offered as a resume only where the run reported a session to resume; otherwise the door is
                // run again from its start, which is what it actually does.
                if record.sessionID != nil, let jobs {
                    return ResumeOffer(id: record.id, title: record.title,
                                       subtitle: "\(record.agent) · \(record.stateLabel) · continues its own session",
                                       tone: .ended) {
                        guard jobs.resumeFromRecord(record) != nil else { return }
                        done()
                    }
                }
                guard let door = record.door, !door.isEmpty, let jobs else { return nil }
                return ResumeOffer(id: record.id, title: record.title,
                                   subtitle: "\(record.agent) · runs \(door) again from the beginning",
                                   tone: .ended) {
                    jobs.start(door: door, title: record.title, agent: record.agent,
                               permission: record.permission.flatMap(RunPermission.init(rawValue:)) ?? .readOnly,
                               directory: record.directory, subject: record.subject,
                               mode: record.mode.flatMap(RunMode.init(rawValue:)) ?? .standard)
                    done()
                }
            case .terminalSession:
                // A `/dev` run is recorded under its run id, the card under its number; both must find the task.
                guard let task = model.tasks.first(where: { $0.id == record.id || DoorRuns.id(for: $0) == record.id })
                else { return nil }
                let resume = AgentResume.command(for: record.executable)
                return ResumeOffer(id: record.id, title: record.title,
                                   subtitle: resume.map { "\($0.name) · \(record.stateLabel) · runs `\($0.line)` in its worktree" }
                                       ?? "Terminal · \(record.stateLabel) · a shell in its worktree, starting fresh",
                                   tone: .ended) {
                    open(task: task, running: resume?.line, model: model, terminals: terminals,
                         worktreeLocation: worktreeLocation, show: show)
                    done()
                }
            }
        }
    }

    /// A task that was started and is not running now: its worktree is on disk with its branch checked out,
    /// and picking it up again is opening a session in it. The board's own columns say which those are, so
    /// the dock asks them rather than keeping a "paused" flag nothing else would maintain.
    private static func paused(model: ProjectWindowModel, terminals: ShellTerminalRegistry?,
                               worktreeLocation: String, show: @escaping (String) -> Void) -> [ResumeOffer] {
        model.tasks.filter { task in
            task.column == .inProgress && task.branch != nil
                && !model.sessions.state(for: task.id).isLive
                && !model.sessions.activeTaskIDs.contains(task.id)
        }.map { task in
            ResumeOffer(id: "paused:\(task.id)", title: task.title,
                        subtitle: "Paused at \(task.column.title) · \(task.branch ?? "")", tone: .waiting) {
                open(task: task, running: nil, model: model, terminals: terminals,
                     worktreeLocation: worktreeLocation, show: show)
            }
        }
    }

    /// A shell in the task's own worktree — the folder the work was left in, with its branch checked out. The
    /// agent's conversation is the CLI's to restore, which is what `running` is for.
    private static func open(task: DeskTask, running line: String?, model: ProjectWindowModel,
                             terminals: ShellTerminalRegistry?, worktreeLocation: String,
                             show: @escaping (String) -> Void) {
        guard let terminals else { return }
        if model.sessions.state(for: task.id).isLive { show(task.id); return }
        Task {
            await model.sessions.start(taskID: task.id, branch: task.branch, taskNumber: task.taskNumber,
                                       noBranchNote: task.noBranchNote, worktreeLocation: worktreeLocation,
                                       title: task.title, baseRef: task.baseRef)
            guard case .running(let folder) = model.sessions.state(for: task.id) else { return }
            terminals.start(taskID: task.id, folder: folder.url)
            show(task.id)
            guard let line else { return }
            // A login shell reads nothing until it has drawn its first prompt; typed sooner the line is
            // swallowed, and zsh mid-setup answers with "error on TTY read: invalid argument" and exits 1.
            try? await Task.sleep(for: .milliseconds(700))
            terminals.sendCommand(line, to: task.id)
        }
    }
}

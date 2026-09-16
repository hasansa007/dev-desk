import DeskCore
import SwiftUI
import UserNotifications

/// What a background run does when nobody is looking at it. A run that stops to ask a question, one that
/// finishes and one that fails were all silent: you found out by opening Terminals and reading a row.
///
/// Terminal sessions report through their agent's hooks (`AgentHooks`), their own exit, or the bell, and are
/// posted by `post(_:session:…)` under the same three toggles and the same sound.
@MainActor
enum RunNotifications {
    /// Tied to the run, so clicking a notification can open the window that owns it.
    private static let jobKey = "desk.jobID"
    private static let directoryKey = "desk.directory"

    static let sessionKey = "desk.sessionID"
    static let projectDirectoryKey = directoryKey
    /// Posted when a notification is clicked, with its `userInfo`; the window for that directory selects the session.
    static let openSession = Notification.Name("desk.openSession")

    static func attach(to jobs: JobRegistry) {
        jobs.onSettled = { job in post(for: job) }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func wants(_ key: String) -> Bool { UserDefaults.standard.object(forKey: key) as? Bool ?? true }

    /// A terminal session's event. `isOnScreen` skips the banner for what the developer is already looking at; the
    /// sound still plays, as asked for on 2026-09-17.
    static func post(_ event: TerminalEvent, session id: String, name: String, directory: String, isOnScreen: Bool) {
        let content = UNMutableNotificationContent()
        switch event {
        case .question(let message):
            guard wants(PreferenceKey.notifyDecisions) else { return }
            content.title = "\(name) needs you"
            content.body = message ?? "It is waiting for an answer."
        case .bell:
            guard wants(PreferenceKey.notifyDecisions) else { return }
            content.title = "\(name) rang the bell"
            content.body = "It may be waiting for you."
        case .turnFinished:
            guard wants(PreferenceKey.notifyCompletion) else { return }
            content.title = "\(name) finished its turn"
            content.body = "It is waiting for your next message."
        case .exited(let status) where status == 0:
            guard wants(PreferenceKey.notifyCompletion) else { return }
            content.title = "\(name) finished"
            content.body = "The session ended."
        case .exited(let status):
            guard wants(PreferenceKey.notifyFailures) else { return }
            content.title = "\(name) stopped with an error"
            content.body = "It exited with status \(status)."
        }
        NotificationSound.play()
        guard !isOnScreen else { return }
        content.subtitle = (directory as NSString).lastPathComponent
        content.userInfo = [sessionKey: id, directoryKey: directory]
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    private static func post(for job: BackgroundJob) {
        guard let content = content(for: job) else { return }
        NotificationSound.play()
        content.userInfo = [jobKey: job.id, directoryKey: job.directory]
        let request = UNNotificationRequest(identifier: job.id + "-" + stateKey(job.state), content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    /// nil when this state is one the developer asked not to hear about.
    private static func content(for job: BackgroundJob) -> UNMutableNotificationContent? {
        let content = UNMutableNotificationContent()
        switch job.state {
        case .asking(let question):
            guard wants(PreferenceKey.notifyDecisions) else { return nil }
            content.title = "\(job.title) needs an answer"
            content.body = question
        case .ended(let text, let failed) where failed:
            guard wants(PreferenceKey.notifyFailures) else { return nil }
            content.title = "\(job.title) failed"
            content.body = text
        case .ended(let text, _):
            guard wants(PreferenceKey.notifyCompletion) else { return nil }
            content.title = "\(job.title) finished"
            content.body = text
        case .starting, .running:
            return nil
        }
        content.subtitle = (job.directory as NSString).lastPathComponent
        return content
    }

    /// One notification per state per run: asking twice about the same question is noise, but a run that asks,
    /// is answered and asks again is two questions.
    private static func stateKey(_ state: JobState) -> String {
        switch state {
        case .asking(let question): return "asking-\(question.hashValue)"
        case .ended(_, let failed): return failed ? "failed" : "finished"
        case .starting: return "starting"
        case .running: return "running"
        }
    }
}

/// The sound every notification makes, played by the app rather than attached to the notification: a system sound
/// by name is not one `UNNotificationSound` can find, and a banner skipped for an on-screen session still sounds.
@MainActor
enum NotificationSound {
    static let defaultName = "Glass"
    static let choices = ["Basso", "Blow", "Bottle", "Frog", "Funk", "Glass", "Hero", "Morse", "Ping", "Pop", "Purr",
                          "Sosumi", "Submarine", "Tink"]
    private static var last = Date.distantPast

    /// At most once a second, so several events arriving together sound once.
    static func play(_ name: String? = nil) {
        let chosen = name ?? (UserDefaults.standard.string(forKey: PreferenceKey.notifySound) ?? defaultName)
        guard !chosen.isEmpty, name != nil || Date().timeIntervalSince(last) > 1 else { return }
        last = Date()
        NSSound(named: NSSound.Name(chosen))?.play()
    }
}

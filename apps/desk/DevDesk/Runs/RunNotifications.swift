import DeskCore
import SwiftUI
import UserNotifications

/// What a background run does when nobody is looking at it. A run that stops to ask a question, one that
/// finishes and one that fails were all silent: you found out by opening Terminals and reading a row.
///
/// The three toggles this reads have existed since the navigation spec, under a caption saying the app did not
/// run managed work yet — it has since ADR 0025. Sessions in a terminal are not here: the app sees them as
/// bytes, and cannot tell working from waiting until the doors report it themselves.
@MainActor
enum RunNotifications {
    /// Tied to the run, so clicking a notification can open the window that owns it.
    private static let jobKey = "desk.jobID"
    private static let directoryKey = "desk.directory"

    static func attach(to jobs: JobRegistry) {
        jobs.onSettled = { job in post(for: job) }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private static func post(for job: BackgroundJob) {
        guard let content = content(for: job) else { return }
        content.userInfo = [jobKey: job.id, directoryKey: job.directory]
        let request = UNNotificationRequest(identifier: job.id + "-" + stateKey(job.state), content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    /// nil when this state is one the developer asked not to hear about.
    private static func content(for job: BackgroundJob) -> UNMutableNotificationContent? {
        let defaults = UserDefaults.standard
        func wants(_ key: String) -> Bool { defaults.object(forKey: key) as? Bool ?? true }
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

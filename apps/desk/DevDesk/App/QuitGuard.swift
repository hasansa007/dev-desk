import AppKit
import DeskCore
import SwiftUI
import UserNotifications

/// Quitting used to end every agent and every background run without a word: `endAllBeforeQuit` fires on
/// `willTerminate`, by which point the decision is already made. An agent mid-task is minutes of work and
/// tokens already spent, so quit asks first — and only ever when something is actually live.
@MainActor
final class QuitGuard: NSObject, NSApplicationDelegate {
    /// The app's background runs, handed over once the scene that owns them exists.
    static var jobs: JobRegistry?

    /// What is running right now, as the alert would say it, or nil when nothing is.
    static var liveWork: String? {
        let sessions = LiveShells.shared.agentCount
        let background = jobs?.liveCount ?? 0
        let parts = [sessions > 0 ? "\(sessions) \(sessions == 1 ? "session" : "sessions")" : nil,
                     background > 0 ? "\(background) background \(background == 1 ? "run" : "runs")" : nil]
            .compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " and ")
    }

    static var confirmsQuit: Bool {
        UserDefaults.standard.object(forKey: PreferenceKey.confirmQuit) as? Bool ?? true
    }

    /// Held for the app's lifetime: dropping it would stop the app-icon appearance observation.
    private var appearanceObservation: NSKeyValueObservation?

    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
        RunNotifications.requestPermission()
        // Re-assert the chosen icon on every launch: a reinstall dittos a fresh bundle over this one
        // and wipes any custom icon, so a launch is the only moment the preference can restore it.
        // This is the earliest the preference can speak, not the last word on it — see
        // applicationDidBecomeActive, which repaints the tile once AppKit can no longer overwrite it.
        AppIconStyle.apply()
        // When the icon choice is System, a live OS light/dark switch has to re-resolve it. Observe
        // the app's effective appearance rather than a notification, so the value is read after AppKit
        // has already flipped it.
        appearanceObservation = NSApp.observe(\.effectiveAppearance) { _, _ in
            Task { @MainActor in AppIconStyle.apply() }
        }
    }

    /// Repaint the Dock tile once the app is active, where AppKit will not paint over the choice again.
    ///
    /// A Force Quit destroys `NSApp.applicationIconImage`, and the on-disk custom icon it should have
    /// fallen back on has been found torn empty by the same kill — so after a hard kill the next launch
    /// is the only thing that can put the chosen artwork back, and it has to do it by repainting the
    /// live tile. `applicationDidFinishLaunching` is too early to be trusted with that alone: AppKit can
    /// still paint the tile from the bundle after it returns and leave the shipped light icon up. This
    /// fires after that paint. It also fires on every later activation, which costs a resolve and
    /// assigns the same image — `AppIconStyle.apply` is idempotent, so no flag is kept here that could
    /// fall out of step with the appearance observer calling the very same method.
    func applicationDidBecomeActive(_ notification: Notification) {
        AppIconStyle.apply()
    }

    /// The background runs' half of the graceful-quit mark (ADR 0031); `LiveShells.endAllBeforeQuit` does the
    /// sessions'. A quit is the app ending on its own terms, so nothing here should come back next launch as a
    /// crash to recover from — and a force-kill, which runs none of this, should.
    func applicationWillTerminate(_ notification: Notification) {
        Self.jobs?.markAllClean()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard Self.confirmsQuit, let work = Self.liveWork else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "\(work) still running"
        alert.informativeText = "Quitting ends them. An agent's work in its worktree is kept; what it had not finished is lost."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Quit anyway")
        alert.addButton(withTitle: "Cancel")
        // The default is Cancel: the destructive answer should not be the one a stray Return sends.
        alert.buttons.last?.keyEquivalent = "\r"
        alert.buttons.first?.keyEquivalent = ""
        return alert.runModal() == .alertFirstButtonReturn ? .terminateNow : .terminateCancel
    }
}

/// Banners show while the app is in front too — a session in another window or tab is still news — and a click
/// brings the app forward and hands the session to the window that owns it.
extension QuitGuard: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        let session = info[RunNotifications.sessionKey] as? String ?? info["desk.jobID"] as? String
        let directory = info[RunNotifications.projectDirectoryKey] as? String
        DispatchQueue.main.async {
            NSApp.activate()
            NotificationCenter.default.post(name: RunNotifications.openSession, object: nil,
                                            userInfo: ["session": session as Any, "directory": directory as Any])
            completionHandler()
        }
    }
}

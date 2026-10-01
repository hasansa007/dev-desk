import AppKit
import DeskCore
import SwiftUI
import UserNotifications

/// Quit is the one way out, and it asks (ADR 0063). ⌘W used to close the window, which with one window is
/// the whole app, without a word; it is gone, and the window's close button is a quit. What was live is kept
/// at quit as a record the next launch offers to resume — `endAllBeforeQuit` and `applicationWillTerminate`.
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
    private var keyObserver: NSObjectProtocol?

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
        // SwiftUI creates the window after launch and may recreate it, so its close button is taken over each
        // time a window becomes key rather than once.
        keyObserver = NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification,
                                                             object: nil, queue: .main) { note in
            MainActor.assumeIsolated { (note.object as? NSWindow).map(Self.routeCloseToQuit) }
        }
    }

    /// The workspace window's close button quits — through `applicationShouldTerminate`, so it asks — instead
    /// of closing the only window and taking every session with it unasked. Sheets and panels keep theirs.
    private static func routeCloseToQuit(_ window: NSWindow) {
        guard window.identifier?.rawValue.hasPrefix("workspace") == true,
              let close = window.standardWindowButton(.closeButton) else { return }
        close.target = NSApp
        close.action = #selector(NSApplication.terminate(_:))
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

    /// The background runs' half of the quit mark (ADR 0063); `LiveShells.endAllBeforeQuit` does the sessions'.
    /// Each live run's record stays, marked saved at quit, so the next launch offers it back to resume.
    func applicationWillTerminate(_ notification: Notification) {
        Self.jobs?.markAllSavedAtQuit()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // A logout, restart or shutdown has already been decided; a modal here would only stall it.
        guard Self.confirmsQuit, !Self.isSystemEnding else { return .terminateNow }
        let work = Self.liveWork
        let alert = NSAlert()
        alert.messageText = "Quit Dev Desk?"
        alert.informativeText = work.map {
            "\($0) running. Each is saved as it stands and offered to resume when Dev Desk opens again; what an agent was in the middle of stops now."
        } ?? "Nothing is running."
        alert.alertStyle = work == nil ? .informational : .warning
        alert.addButton(withTitle: "Quit")
        alert.addButton(withTitle: "Cancel")
        // With something live the default is Cancel, so a stray Return does not stop an agent mid-turn.
        if work != nil {
            alert.buttons.last?.keyEquivalent = "\r"
            alert.buttons.first?.keyEquivalent = ""
        }
        return alert.runModal() == .alertFirstButtonReturn ? .terminateNow : .terminateCancel
    }

    /// Whether this quit is the system's — logout, restart or shutdown — rather than the developer's.
    private static var isSystemEnding: Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent,
              event.eventID == kAEQuitApplication,
              let reason = event.attributeDescriptor(forKeyword: kAEQuitReason)?.enumCodeValue else { return false }
        return [kAELogOut, kAEReallyLogOut, kAEShowRestartDialog, kAEShowShutdownDialog, kAERestart, kAEShutDown]
            .contains(reason)
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

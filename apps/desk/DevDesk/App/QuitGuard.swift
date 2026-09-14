import AppKit
import DeskCore
import SwiftUI

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
        // Re-assert the chosen icon on every launch: a reinstall dittos a fresh bundle over this one
        // and wipes any custom icon, so a launch is the only moment the preference can restore it.
        AppIconStyle.apply()
        // When the icon choice is System, a live OS light/dark switch has to re-resolve it. Observe
        // the app's effective appearance rather than a notification, so the value is read after AppKit
        // has already flipped it.
        appearanceObservation = NSApp.observe(\.effectiveAppearance) { _, _ in
            Task { @MainActor in AppIconStyle.apply() }
        }
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

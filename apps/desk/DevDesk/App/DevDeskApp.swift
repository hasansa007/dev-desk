import DeskCore
import SwiftUI

@main
struct DevDeskApp: App {
    @NSApplicationDelegateAdaptor(QuitGuard.self) private var quitGuard
    @State private var registry = OpenProjectRegistry()
    /// Owned by the app, never by a window: a background run outlives the project window that started it, and
    /// ends at quit with everything else (ADR 0025).
    @State private var jobs = JobRegistry(spawner: ProcessJobSpawner())

    var body: some Scene {
        Window("Open Project", id: "launcher") {
            LauncherView(context: .window)
                .environment(registry)
                .modifier(SnapshotBootstrap())
        }
        // .contentSize pinned the launcher to its ideal size, so it could not be made smaller than
        // the display it had to fit on.
        .windowResizability(.contentMinSize)
        .defaultPosition(.center)

        WindowGroup(for: ProjectRef.self) { $ref in
            Group {
                if let ref {
                    ProjectWindow(ref: ref)
                } else {
                    LauncherView(context: .window)
                }
            }
            .environment(registry)
            .environment(jobs)
            // AppKit makes the delegate before any scene exists, so it is told where the app's runs live.
            .task {
                QuitGuard.jobs = jobs
                RunNotifications.attach(to: jobs)
                // The registry spans projects; a journal is one project's folder. The app is the only place
                // that can map one to the other, so it hands the registry the mapping (ADR 0031).
                jobs.journalFor = { directory in
                    directory.isEmpty ? nil : RunJournal(projectRoot: URL(fileURLWithPath: directory, isDirectory: true))
                }
            }
        }
        .defaultSize(width: 1440, height: 900)
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands { DeskCommands() }
    }
}

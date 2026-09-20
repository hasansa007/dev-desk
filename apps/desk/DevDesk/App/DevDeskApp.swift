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
        // One window holds every project (ADR 0050). It was a `WindowGroup` keyed by `ProjectRef` — a window
        // per project — and the launcher was a second window beside it; the strip replaced both, so Open
        // project is a sheet on this one and Home is what it shows with nothing selected.
        Window("Dev Desk", id: "workspace") {
            WorkspaceWindow()
                .environment(registry)
                .environment(jobs)
                .modifier(SnapshotBootstrap())
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

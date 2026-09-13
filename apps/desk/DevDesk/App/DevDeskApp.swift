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
        .windowResizability(.contentSize)
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
            .task { QuitGuard.jobs = jobs }
        }
        .defaultSize(width: 1440, height: 900)
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands { DeskCommands() }
    }
}

import DeskCore
import SwiftUI

@main
struct DevDeskApp: App {
    @State private var registry = OpenProjectRegistry()

    var body: some Scene {
        Window("Open Project", id: "launcher") {
            LauncherView(context: .window)
                .environment(registry)
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
        }
        .defaultSize(width: 1440, height: 900)
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands { DeskCommands() }
    }
}

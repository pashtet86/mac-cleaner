import SwiftUI

@main
struct MacOptimizerApp: App {
    @State private var cleanup = CleanupStore()
    @State private var simulators = SimulatorsStore()
    @State private var docker = DockerStore()
    @State private var files = FilesStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(cleanup)
                .environment(simulators)
                .environment(docker)
                .environment(files)
                .frame(minWidth: 860, minHeight: 600)
        }
        .defaultSize(width: 1120, height: 780)
        .windowToolbarStyle(.unified)
    }
}

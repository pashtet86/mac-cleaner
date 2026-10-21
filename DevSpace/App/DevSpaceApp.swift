import SwiftUI

@main
struct DevSpaceApp: App {
    @State private var cleanup = CleanupStore()
    @State private var simulators = SimulatorsStore()
    @State private var docker = DockerStore()
    @State private var files = FileScans()
    @State private var inspector = InspectorStore()
    @State private var thermals = ThermalStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(cleanup)
                .environment(simulators)
                .environment(docker)
                .environment(files)
                .environment(inspector)
                .environment(thermals)
                .frame(minWidth: 860, minHeight: 600)
        }
        .defaultSize(width: 1120, height: 780)
        .windowToolbarStyle(.unified)
    }
}

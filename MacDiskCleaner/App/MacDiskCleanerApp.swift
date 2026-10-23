import SwiftUI

@main
struct MacDiskCleanerApp: App {
    @State private var cleanup = CleanupStore()
    @State private var simulators = SimulatorsStore()
    @State private var docker = DockerStore()
    @State private var files = FileScans()
    @State private var inspector = InspectorStore()
    @State private var thermals = ThermalStore()
    @State private var apps = AppsStore()
    @State private var environments = EnvironmentsStore()
    @State private var security = SecurityStore()
    @State private var network = NetworkStore()
    private let updater = Updater.shared

    var body: some Scene {
        WindowGroup("Disk Cleaner") {
            RootView()
                .environment(cleanup)
                .environment(simulators)
                .environment(docker)
                .environment(files)
                .environment(inspector)
                .environment(thermals)
                .environment(apps)
                .environment(environments)
                .environment(security)
                .environment(network)
                .frame(minWidth: 860, minHeight: 600)
        }
        .defaultSize(width: 1120, height: 780)
        .windowToolbarStyle(.unified)
        .commands {
            // The sidebar is always shown, so View → Hide Sidebar has nothing to do.
            CommandGroup(replacing: .sidebar) {}
            CommandGroup(after: .appInfo) {
                if updater.isAvailable {
                    Button("Check for Updates") { updater.checkForUpdates() }
                        .disabled(!updater.canCheck)
                }
            }
        }

        Settings {
            SettingsView()
        }
    }
}

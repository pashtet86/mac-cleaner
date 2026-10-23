import SwiftUI

enum AppSection: String, Hashable, CaseIterable {
    case overview, environments, files, inspector, apps, applications, xcode, simulators, ides, docker, packages,
        largeFiles,
        duplicates,
        security, network

    static let health: [AppSection] = [.environments, .security, .network]
    /// Everything that frees space by itself: one "Clean" group.
    static let clean: [AppSection] = [.apps, .xcode, .simulators, .ides, .packages, .docker]
    static let mac: [AppSection] = [.applications, .files]
    static let available: [AppSection] = [.overview] + clean + mac + health

    var title: String {
        switch self {
        case .overview: "Overview"
        case .environments: "Environments"
        case .files: "Files"
        case .inspector: "Files Inspector"
        case .apps: "App Caches"
        case .applications: "Applications"
        case .xcode: "Xcode"
        case .simulators: "Simulators"
        case .ides: "IDEs"
        case .docker: "Docker"
        case .packages: "Packages & Toolchains"
        case .largeFiles: "Large Files"
        case .duplicates: "Duplicates"
        case .security: "Security"
        case .network: "Network"
        }
    }

    /// Page heading: says what the page cleans.
    var pageTitle: String {
        switch self {
        case .environments: "Environment Health"
        case .security: "Security Check"
        case .network: "Network Check"
        case .apps: "App Cache Cleanup"
        case .applications: "Application Cleanup"
        case .xcode: "Xcode Cleanup"
        case .simulators: "Simulator Cleanup"
        case .ides: "IDE Cleanup"
        case .packages: "Package & Toolchain Cleanup"
        case .docker: "Docker Cleanup"
        case .largeFiles: "Large File Cleanup"
        case .duplicates: "Duplicate Cleanup"
        default: title
        }
    }

    var symbol: String {
        switch self {
        case .overview: "gauge.with.dots.needle.50percent"
        case .inspector: "square.split.bottomrightquarter"
        case .environments: "stethoscope"
        case .files: "folder"
        case .apps: "tray.full"
        case .applications: "app.dashed"
        case .xcode: "hammer"
        case .simulators: "ipad.and.iphone"
        case .ides: "curlybraces.square"
        case .docker: "square.stack.3d.up"
        case .packages: "shippingbox"
        case .largeFiles: "square.resize.up"
        case .duplicates: "doc.on.doc"
        case .security: "lock.shield"
        case .network: "network"
        }
    }

    var summary: String {
        switch self {
        case .apps: "Caches and logs that apps rebuild themselves."
        case .applications: "Installed apps with their size and when you last opened them."
        case .environments: "Node, Java, Python, Ruby, Homebrew and more — what's out of date and how urgent it is."
        case .files: "Large files, duplicates and a map of your folders."
        case .xcode: "Build products, previews, device symbols and archives."
        case .simulators: "Runtimes and devices managed by Xcode."
        case .docker: "Images, containers and build cache."
        case .ides: "Android Studio and SDK, JetBrains IDEs, VS Code, Cursor and Zed."
        case .packages: "npm, CocoaPods, Gradle, Cargo, Maven, Go, pip, Homebrew and more."
        case .largeFiles: "The biggest files: videos, installers, disk images and archives."
        case .duplicates: "Byte-identical copies of the same file."
        case .security: "macOS protections and everything that starts by itself, with who signed it."
        case .network: "Firewall, and which apps accept connections from other devices."
        case .inspector: "A map of what fills your disk — open folders, see what is safe to delete."
        case .overview: ""
        }
    }

    /// Entity color — the same hue in the sidebar, cards and every chart.
    var tint: Color {
        switch self {
        case .xcode: Theme.indigo
        case .packages: Theme.teal
        case .apps: Theme.ochre
        case .simulators: Theme.rose
        case .ides: Theme.lavender
        case .docker, .overview, .inspector, .applications, .largeFiles, .duplicates, .environments, .files,
            .security, .network:
            Theme.accent
        }
    }

    var ruleSection: RuleSection? {
        switch self {
        case .apps: .apps
        case .xcode: .xcode
        case .ides: .ides
        case .packages: .packages
        default: nil
        }
    }
}

struct RootView: View {
    @State private var selection: AppSection? = .overview
    @Environment(FileScans.self) private var files
    @Environment(CleanupStore.self) private var cleanup
    @Environment(SimulatorsStore.self) private var simulators
    @Environment(DockerStore.self) private var docker
    @Environment(AppsStore.self) private var apps
    @Environment(EnvironmentsStore.self) private var environments
    @Environment(SecurityStore.self) private var security
    @Environment(NetworkStore.self) private var network
    @Environment(InspectorStore.self) private var inspector

    /// Narrower than this and the disk line in the sidebar footer no longer fits.
    static let sidebarMinimum: CGFloat = 220
    static let sidebarMaximum: CGFloat = 300

    private var availability: SectionAvailability {
        SectionAvailability(
            cleanup: cleanup, simulators: simulators, docker: docker, apps: apps, environments: environments,
            security: security, network: network)
    }

    var body: some View {
        // The sidebar is always visible: no toggle, and the visibility can't change.
        NavigationSplitView(columnVisibility: .constant(.all)) {
            // List on top, sensors pinned flush to the bottom edge.
            VStack(spacing: 0) {
                List(selection: $selection) {
                    Section {
                        row(.overview)
                    }
                    Section("Clean") {
                        ForEach(availability.visible(AppSection.clean, keeping: selection), id: \.self, content: row)
                        if availability.isDetecting {
                            Label {
                                Text("Detecting").foregroundStyle(.tertiary)
                            } icon: {
                                ProgressView().controlSize(.mini)
                            }
                            .selectionDisabled()
                        }
                    }
                    Section("Mac") {
                        ForEach(AppSection.mac, id: \.self, content: row)
                    }
                    Section("Mac Health") {
                        ForEach(AppSection.health, id: \.self, content: row)
                    }
                }
                .animation(.snappy, value: availability.visible(AppSection.clean, keeping: nil))
                .frame(maxHeight: .infinity)
                Divider().overlay(Theme.hairline)
                ThermalFooter()
                    .fixedSize(horizontal: false, vertical: true)
            }
            .navigationSplitViewColumnWidth(min: Self.sidebarMinimum, ideal: 236, max: Self.sidebarMaximum)
            .toolbar(removing: .sidebarToggle)
            // Dragging the divider can't collapse it either.
            .background(SidebarLock(minimum: Self.sidebarMinimum, maximum: Self.sidebarMaximum))
        } detail: {
            let section = selection ?? .overview
            switch section {
            case .overview: OverviewView(selection: $selection)
            case .inspector: InspectorView()
            case .applications: AppsView()
            case .files: FilesHubView()
            case .environments: EnvironmentsView()
            case .apps, .xcode, .ides, .packages: RulesPage(section: section).id(section)
            case .simulators: SimulatorsView()
            case .largeFiles: LargeFilesView(store: files.large)
            case .duplicates: DuplicatesView(store: files.duplicates)
            case .docker: DockerView()
            case .security: SecurityView()
            case .network: NetworkView()
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) { VersionBadge() }
                .sharedBackgroundVisibility(.hidden)
        }
        .tint(Theme.accent)
        .task {
            Telemetry.shared.appOpened()
            await availability.detectAll()
        }
        #if DEBUG
        .task {
            await DebugSnapshot.run(
                select: { selection = $0 }, files: files, inspector: inspector, environments: environments)
        }
        #endif
    }

    private func row(_ section: AppSection) -> some View {
        let attention = availability.attentionMessage(for: section)
        // One neutral icon color; a small badge on the icon's top-left corner marks attention.
        return Label {
            Text(section.title)
        } icon: {
            // A concrete color: hierarchical `.primary` in a sidebar picks up the accent tint.
            Image(systemName: section.symbol)
                .foregroundStyle(Color(nsColor: .labelColor))
                .overlay(alignment: .topLeading) {
                    if attention != nil {
                        AttentionDot(size: 5)
                            .offset(x: -3, y: -2)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .animation(.hover, value: attention != nil)
        }
        .help(attention ?? "")
        .tag(section)
    }
}

/// Top-right corner of the window: the app version, or a quiet "Update to x.y" button once the
/// daily background check found a new version.
private struct VersionBadge: View {
    private let updater = Updater.shared

    var body: some View {
        if let pending = updater.pendingVersion {
            Button {
                updater.checkForUpdates()
            } label: {
                Label("Update to \(pending)", systemImage: "arrow.down.circle.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.cleanable)
            }
            .buttonStyle(.plain)
            .help("Disk Cleaner \(pending) is available — see what's new and install it")
        } else {
            Text("Version \(updater.version)")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .help(updater.isAvailable ? "Disk Cleaner checks for updates once a day" : "Build \(updater.build)")
        }
    }
}

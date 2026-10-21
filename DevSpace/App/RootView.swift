import SwiftUI

enum AppSection: String, Hashable, CaseIterable {
    case overview, inspector, apps, applications, xcode, simulators, ides, docker, packages, largeFiles, duplicates,
        security, network

    static let mac: [AppSection] = [.apps, .applications, .largeFiles, .duplicates, .inspector]
    static let developer: [AppSection] = [.xcode, .simulators, .ides, .packages, .docker]
    static let upcoming: [AppSection] = [.security, .network]
    static let available: [AppSection] = [.overview] + mac + developer

    var title: String {
        switch self {
        case .overview: "Overview"
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
        case .xcode: "Build products, previews, device symbols and archives."
        case .simulators: "Runtimes and devices managed by Xcode."
        case .docker: "Images, containers and build cache."
        case .ides: "Android Studio and SDK, JetBrains IDEs, VS Code, Cursor and Zed."
        case .packages: "npm, CocoaPods, Gradle, Cargo, Maven, Go, pip, Homebrew and more."
        case .largeFiles: "The biggest files: videos, installers, disk images and archives."
        case .duplicates: "Byte-identical copies of the same file."
        case .security: "Launch agents, login items and code signatures."
        case .network: "Listening ports and firewall status."
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
        case .docker, .overview, .inspector, .applications, .largeFiles, .duplicates: Theme.accent
        default: .secondary
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
    @Environment(InspectorStore.self) private var inspector

    private var availability: SectionAvailability {
        SectionAvailability(cleanup: cleanup, simulators: simulators, docker: docker, apps: apps)
    }

    var body: some View {
        // The sidebar is always visible: no toggle, and the visibility can't change.
        NavigationSplitView(columnVisibility: .constant(.all)) {
            List(selection: $selection) {
                Section {
                    row(.overview)
                }
                Section("Clean Mac") {
                    ForEach(availability.visible(AppSection.mac, keeping: selection), id: \.self, content: row)
                }
                Section("Clean Dev Tools") {
                    ForEach(availability.visible(AppSection.developer, keeping: selection), id: \.self, content: row)
                    if availability.isDetecting {
                        Label {
                            Text("Detecting…").foregroundStyle(.tertiary)
                        } icon: {
                            ProgressView().controlSize(.mini)
                        }
                        .selectionDisabled()
                    }
                }
                Section("Soon") {
                    ForEach(AppSection.upcoming, id: \.self) { section in
                        Label(section.title, systemImage: section.symbol)
                            .foregroundStyle(.tertiary)
                            .selectionDisabled()
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 224, max: 260)
            .toolbar(removing: .sidebarToggle)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 0) {
                    Divider().overlay(Theme.hairline)
                    ThermalFooter()
                }
            }
            .animation(.snappy, value: availability.visible(AppSection.mac + AppSection.developer, keeping: nil))
        } detail: {
            let section = selection ?? .overview
            switch section {
            case .overview: OverviewView(selection: $selection)
            case .inspector: InspectorView()
            case .applications: AppsView()
            case .apps, .xcode, .ides, .packages: RulesPage(section: section).id(section)
            case .simulators: SimulatorsView()
            case .largeFiles: LargeFilesView(store: files.large)
            case .duplicates: DuplicatesView(store: files.duplicates)
            case .docker: DockerView()
            default: EmptyNote(symbol: "hourglass", title: "Coming soon", message: "")
            }
        }
        .tint(Theme.accent)
        .task { await availability.detectAll() }
        #if DEBUG
        .task { await DebugSnapshot.run(select: { selection = $0 }, files: files, inspector: inspector) }
        #endif
    }

    private func row(_ section: AppSection) -> some View {
        let attention = availability.attention(for: section)
        return Label {
            HStack {
                Text(section.title)
                Spacer(minLength: 4)
                if let attention {
                    AttentionDot()
                        .help("\(attention.formattedBytes) safe to clean")
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(.hover, value: attention != nil)
        } icon: {
            Image(systemName: section.symbol).foregroundStyle(section.tint)
        }
        .tag(section)
    }
}

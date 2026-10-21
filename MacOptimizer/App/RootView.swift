import SwiftUI

enum AppSection: String, Hashable, CaseIterable {
    case overview, apps, xcode, simulators, ides, docker, packages, largeFiles, security, network

    static let mac: [AppSection] = [.apps, .largeFiles]
    static let developer: [AppSection] = [.xcode, .simulators, .ides, .packages, .docker]
    static let upcoming: [AppSection] = [.security, .network]
    static let available: [AppSection] = [.overview] + mac + developer

    var title: String {
        switch self {
        case .overview: "Overview"
        case .apps: "App Caches"
        case .xcode: "Xcode"
        case .simulators: "Simulators"
        case .ides: "IDEs"
        case .docker: "Docker"
        case .packages: "Packages & Toolchains"
        case .largeFiles: "Large Files & Duplicates"
        case .security: "Security"
        case .network: "Network"
        }
    }

    var symbol: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .apps: "sparkles"
        case .xcode: "hammer"
        case .simulators: "iphone"
        case .ides: "chevron.left.forwardslash.chevron.right"
        case .docker: "shippingbox.and.arrow.backward"
        case .packages: "cube.box"
        case .largeFiles: "doc.on.doc"
        case .security: "checkmark.shield"
        case .network: "network"
        }
    }

    var summary: String {
        switch self {
        case .apps: "Caches and logs that apps rebuild themselves."
        case .xcode: "Build products, previews, device symbols and archives."
        case .simulators: "Runtimes and devices managed by Xcode."
        case .docker: "Images, containers and build cache."
        case .ides: "Android Studio and SDK, JetBrains IDEs, VS Code, Cursor and Zed."
        case .packages: "npm, CocoaPods, Gradle, Cargo, Maven, Go, pip, Homebrew and more."
        case .largeFiles: "Biggest folders, installers and identical files."
        case .security: "Launch agents, login items and code signatures."
        case .network: "Listening ports and firewall status."
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
        case .docker, .overview, .largeFiles: Theme.accent
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
    #if DEBUG
    @Environment(FilesStore.self) private var files
    #endif

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section {
                    row(.overview)
                }
                Section("Mac") {
                    ForEach(AppSection.mac, id: \.self, content: row)
                }
                Section("Developer") {
                    ForEach(AppSection.developer, id: \.self, content: row)
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
        } detail: {
            let section = selection ?? .overview
            switch section {
            case .overview: OverviewView(selection: $selection)
            case .apps, .xcode, .ides, .packages: RulesPage(section: section).id(section)
            case .simulators: SimulatorsView()
            case .largeFiles: FilesView()
            case .docker: DockerView()
            default: EmptyNote(symbol: "hourglass", title: "Coming soon", message: "")
            }
        }
        .tint(Theme.accent)
        #if DEBUG
        .task { await DebugSnapshot.run(select: { selection = $0 }, files: files) }
        #endif
    }

    private func row(_ section: AppSection) -> some View {
        Label {
            Text(section.title)
        } icon: {
            Image(systemName: section.symbol).foregroundStyle(section.tint)
        }
        .tag(section)
    }
}

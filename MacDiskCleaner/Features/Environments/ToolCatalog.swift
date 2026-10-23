import Foundation

/// A developer tool the Environments page knows how to find and judge.
nonisolated struct ToolSpec: Identifiable, Sendable {
    let id: String
    let name: String
    let symbol: String
    let executable: String
    let versionArguments: [String]
    /// endoflife.date product, if the tool has published release lines.
    let lifecycleProduct: String?
    /// 1 when release lines are majors ("24"), 2 when they are major.minor ("3.12").
    let cycleDepth: Int
    /// Folders holding side-by-side versions, relative to home ("~/.nvm/versions/node").
    let managedVersions: [(path: String, source: InstallSource)]

    func updateCommand(for install: Installation, latestInLine: String?) -> String? {
        switch (id, install.source) {
        // Stay on the same major: jumping to a new major can break projects.
        case ("node", .nvm): "nvm install \(install.version.major)"
        case ("node", .fnm): "fnm install \(install.version.major)"
        case ("node", .volta): "volta install node@\(install.version.major)"
        case ("python3", .pyenv): latestInLine.map { "pyenv install \($0)" }
        case ("ruby", .rbenv): latestInLine.map { "rbenv install \($0)" }
        case ("python3", .system): "brew install python"
        case ("ruby", .system): "brew install ruby"
        case ("java", _): "brew install --cask zulu@\(install.version.major)"
        case ("rustc", _), ("cargo", _): "rustup update"
        case ("brew", _): "brew update"
        case ("docker", _): nil  // Docker Desktop updates itself: Docker menu → Check for Updates.
        case (_, .homebrew): "brew upgrade \(homebrewName)"
        case ("npm", _): "npm install -g npm@latest"
        default: nil
        }
    }

    /// Removes an old side-by-side version (the cleaning half of this page).
    func removeCommand(for install: Installation) -> String? {
        switch install.source {
        case .nvm: "nvm uninstall \(install.version)"
        case .fnm: "fnm uninstall \(install.version)"
        case .pyenv: "pyenv uninstall \(install.version)"
        case .rbenv: "rbenv uninstall \(install.version)"
        case .volta: "volta uninstall node@\(install.version)"
        default: nil
        }
    }

    private var homebrewName: String {
        switch id {
        case "python3": "python"
        case "rustc", "cargo": "rust"
        case "pod": "cocoapods"
        default: id
        }
    }

    static let all: [ToolSpec] = [
        ToolSpec(
            id: "node", name: "Node.js", symbol: "hexagon", executable: "node", versionArguments: ["--version"],
            lifecycleProduct: "nodejs", cycleDepth: 1,
            managedVersions: [
                ("~/.nvm/versions/node", .nvm), ("~/Library/Application Support/fnm/node-versions", .fnm),
                ("~/.volta/tools/image/node", .volta), ("~/.asdf/installs/nodejs", .asdf),
            ]),
        ToolSpec(
            id: "npm", name: "npm", symbol: "shippingbox", executable: "npm", versionArguments: ["--version"],
            lifecycleProduct: nil, cycleDepth: 1, managedVersions: []),
        ToolSpec(
            id: "yarn", name: "Yarn", symbol: "shippingbox", executable: "yarn", versionArguments: ["--version"],
            lifecycleProduct: nil, cycleDepth: 1, managedVersions: []),
        ToolSpec(
            id: "pnpm", name: "pnpm", symbol: "shippingbox", executable: "pnpm", versionArguments: ["--version"],
            lifecycleProduct: nil, cycleDepth: 1, managedVersions: []),
        ToolSpec(
            id: "bun", name: "Bun", symbol: "shippingbox", executable: "bun", versionArguments: ["--version"],
            lifecycleProduct: nil, cycleDepth: 1, managedVersions: []),
        ToolSpec(
            id: "deno", name: "Deno", symbol: "shippingbox", executable: "deno", versionArguments: ["--version"],
            lifecycleProduct: nil, cycleDepth: 1, managedVersions: []),
        ToolSpec(
            id: "python3", name: "Python", symbol: "chevron.left.forwardslash.chevron.right", executable: "python3",
            versionArguments: ["--version"], lifecycleProduct: "python", cycleDepth: 2,
            managedVersions: [("~/.pyenv/versions", .pyenv), ("~/.asdf/installs/python", .asdf)]),
        ToolSpec(
            id: "ruby", name: "Ruby", symbol: "chevron.left.forwardslash.chevron.right", executable: "ruby",
            versionArguments: ["--version"], lifecycleProduct: "ruby", cycleDepth: 2,
            managedVersions: [("~/.rbenv/versions", .rbenv), ("~/.asdf/installs/ruby", .asdf)]),
        // Java is found through java_home instead of PATH; see EnvironmentScanner.
        ToolSpec(
            id: "java", name: "Java (JDK)", symbol: "cup.and.saucer", executable: "java", versionArguments: [],
            lifecycleProduct: "eclipse-temurin", cycleDepth: 1, managedVersions: []),
        ToolSpec(
            id: "gradle", name: "Gradle", symbol: "hammer", executable: "gradle", versionArguments: ["--version"],
            lifecycleProduct: "gradle", cycleDepth: 1, managedVersions: []),
        ToolSpec(
            id: "kotlin", name: "Kotlin", symbol: "chevron.left.forwardslash.chevron.right", executable: "kotlin",
            versionArguments: ["-version"], lifecycleProduct: "kotlin", cycleDepth: 2, managedVersions: []),
        ToolSpec(
            id: "go", name: "Go", symbol: "chevron.left.forwardslash.chevron.right", executable: "go",
            versionArguments: ["version"], lifecycleProduct: "go", cycleDepth: 2, managedVersions: []),
        ToolSpec(
            id: "rustc", name: "Rust", symbol: "gearshape.2", executable: "rustc", versionArguments: ["--version"],
            lifecycleProduct: nil, cycleDepth: 2, managedVersions: []),
        ToolSpec(
            id: "pod", name: "CocoaPods", symbol: "leaf", executable: "pod", versionArguments: ["--version"],
            lifecycleProduct: nil, cycleDepth: 1, managedVersions: []),
        ToolSpec(
            id: "flutter", name: "Flutter", symbol: "bird", executable: "flutter", versionArguments: ["--version"],
            lifecycleProduct: nil, cycleDepth: 1, managedVersions: []),
        ToolSpec(
            id: "docker", name: "Docker", symbol: "square.stack.3d.up", executable: "docker",
            versionArguments: ["--version"], lifecycleProduct: "docker-engine", cycleDepth: 1, managedVersions: []),
        ToolSpec(
            id: "git", name: "Git", symbol: "arrow.triangle.branch", executable: "git", versionArguments: ["--version"],
            lifecycleProduct: nil, cycleDepth: 1, managedVersions: []),
        ToolSpec(
            id: "swift", name: "Swift", symbol: "swift", executable: "swift", versionArguments: ["--version"],
            lifecycleProduct: nil, cycleDepth: 1, managedVersions: []),
        ToolSpec(
            id: "brew", name: "Homebrew", symbol: "mug", executable: "brew", versionArguments: ["--version"],
            lifecycleProduct: nil, cycleDepth: 1, managedVersions: []),
    ]

    static func spec(_ id: String) -> ToolSpec? { all.first { $0.id == id } }
}

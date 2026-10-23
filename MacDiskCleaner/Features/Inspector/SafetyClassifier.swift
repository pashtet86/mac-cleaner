import Foundation

/// Explains, for any path in the home folder, how safe it is to delete.
nonisolated struct SafetyClassifier: Sendable {
    private let home: String
    /// Cleanup rule folders, keyed by resolved path.
    private let ruleRoots: [String: CleanupRule]

    init(rules: [CleanupRule], home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.home = home.standardizedFileURL.path
        var roots: [String: CleanupRule] = [:]
        let temp = URL(fileURLWithPath: NSTemporaryDirectory()).standardizedFileURL.path
        for rule in rules {
            for raw in rule.paths {
                // Resolve "~" against this classifier's home so it can be tested with any home.
                var path = raw
                if path.hasPrefix("~/") { path = self.home + path.dropFirst(1) }
                if path.hasPrefix("$TMPDIR") { path = temp + path.dropFirst("$TMPDIR".count) }
                roots[URL(fileURLWithPath: path).standardizedFileURL.path] = rule
            }
        }
        ruleRoots = roots
    }

    /// - Parameters:
    ///   - siblings: names in the same folder, for project-aware checks (`target` next to `Cargo.toml`).
    ///   - parent: the containing folder's verdict, inherited when it is inheritable.
    func classify(path: String, name: String, isDirectory: Bool, siblings: Set<String>, parent: Verdict?) -> Verdict {
        if let parent, parent.inheritable { return parent }

        if path == home {
            return Verdict(safety: .protected, reason: "Your home folder.")
        }
        if SafeTrash.standardHomeFolders.contains(where: { path == home + "/" + $0 }) {
            return Verdict(safety: .protected, reason: "A standard macOS folder — open it to clean what's inside.")
        }
        if path == home + "/.Trash" {
            return Verdict(safety: .protected, reason: "Already in the Trash — empty the Trash to free this space.")
        }

        if let rule = ruleRoots[path] {
            return Verdict(
                safety: .protected,
                reason: "This folder must stay. Its contents are cleanable — see \(rule.title) in Disk Cleaner.")
        }
        let parentPath = (path as NSString).deletingLastPathComponent
        if let rule = ruleRoots[parentPath], ruleIncludes(rule, name: name) {
            return Verdict(
                safety: safety(for: rule.risk), reason: rule.detail, fromCleanupRule: true, inheritable: true)
        }

        if path.hasPrefix(home + "/Library/") {
            return Verdict(safety: .protected, reason: "App data in ~/Library. Remove the app to remove its data.")
        }

        if isDirectory, let verdict = projectArtifact(name: name, siblings: siblings) { return verdict }
        if !isDirectory, let verdict = fileVerdict(name: name, path: path) { return verdict }

        return Verdict(safety: .personal, reason: "Your files — check what's inside before deleting.")
    }

    private func ruleIncludes(_ rule: CleanupRule, name: String) -> Bool {
        if let prefixes = rule.namePrefixes, !prefixes.contains(where: name.hasPrefix) { return false }
        if rule.excludePrefixes?.contains(where: name.hasPrefix) == true { return false }
        return !DiskUsage.isPrivacyProtected(name)
    }

    private func safety(for risk: Risk) -> Safety {
        switch risk {
        case .safe: .rebuildable
        case .probablySafe: .likelySafe
        case .review: .review
        }
    }

    private static let buildCaches: Set<String> = [
        ".next", ".nuxt", ".turbo", ".parcel-cache", ".svelte-kit", ".angular", "__pycache__", ".pytest_cache",
        ".mypy_cache", ".ruff_cache", ".cxx", ".dart_tool", ".build", "DerivedData",
    ]

    private func projectArtifact(name: String, siblings: Set<String>) -> Verdict? {
        let rebuildable = { (reason: String) in
            Verdict(safety: .rebuildable, reason: reason, inheritable: true)
        }
        switch name {
        case "node_modules":
            return rebuildable("JavaScript dependencies — npm, yarn or pnpm install restores them.")
        case "Pods" where siblings.contains("Podfile"):
            return rebuildable("CocoaPods dependencies — pod install restores them.")
        case "target" where siblings.contains("Cargo.toml"):
            return rebuildable("Rust build output — cargo build recreates it.")
        case "target" where siblings.contains("pom.xml"):
            return rebuildable("Maven build output — mvn package recreates it.")
        case "build"
        where !siblings.isDisjoint(with: [
            "build.gradle", "build.gradle.kts", "CMakeLists.txt", "package.json", "pubspec.yaml", "setup.py",
        ]):
            return rebuildable("Build output — the next build recreates it.")
        case ".gradle" where !siblings.isDisjoint(with: ["build.gradle", "build.gradle.kts", "settings.gradle"]):
            return rebuildable("Gradle project cache — recreated on the next build.")
        case "dist",
            "out" where siblings.contains("package.json"):
            return Verdict(
                safety: .likelySafe, reason: "Build output — rebuilt by the project's build script.",
                inheritable: true)
        case ".venv",
            "venv" where !siblings.isDisjoint(with: ["requirements.txt", "pyproject.toml", "setup.py"]):
            return Verdict(
                safety: .likelySafe, reason: "Python virtual environment — recreate it and reinstall packages.",
                inheritable: true)
        default:
            return Self.buildCaches.contains(name) ? rebuildable("Build cache — recreated automatically.") : nil
        }
    }

    private func fileVerdict(name: String, path: String) -> Verdict? {
        switch FileKind.of(URL(fileURLWithPath: path)) {
        case .diskImage:
            let ext = (name as NSString).pathExtension.lowercased()
            let reason =
                ["ipa", "apk", "aab"].contains(ext)
                ? "App build artifact — your project can produce it again."
                : "Installer or disk image — usually not needed once installed."
            return Verdict(safety: .likelySafe, reason: reason)
        case .archive:
            return Verdict(safety: .review, reason: "Archive — make sure you have its contents elsewhere.")
        case .video, .other:
            return nil
        }
    }
}

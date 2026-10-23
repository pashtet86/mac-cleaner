import Foundation

/// Finds installed developer tools. Local only — runs each tool's own version command.
nonisolated enum EnvironmentScanner {
    /// PATH as your login shell sets it. Apps started from Finder get a minimal PATH that misses
    /// Homebrew, nvm and friends, so the tools wouldn't be found without this.
    static func loginEnvironment() async -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let fallback = [
            "/opt/homebrew/bin", "/opt/homebrew/sbin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin",
            "\(home)/.cargo/bin", "\(home)/.volta/bin", "\(home)/.local/bin",
        ].joined(separator: ":")

        // A fixed command — nothing from outside is interpolated. fish can't run it, so it falls back to zsh.
        let userShell = String(cString: getpwuid(getuid()).pointee.pw_shell)
        let shell =
            ["zsh", "bash"].contains(URL(fileURLWithPath: userShell).lastPathComponent) ? userShell : "/bin/zsh"
        let script = #"printf '\n__PATH__%s__END__\n' "$PATH""#
        var path = fallback
        if let result = try? await ProcessRunner.run(shell, ["-ilc", script], timeout: 8),
            let text = String(data: result.stdout, encoding: .utf8),
            let start = text.range(of: "__PATH__"),
            let end = text.range(of: "__END__", range: start.upperBound..<text.endIndex)
        {
            path = String(text[start.upperBound..<end.lowerBound]) + ":" + fallback
        }
        environment["PATH"] = path
        // Never let a version check start a Homebrew self-update or print color codes.
        environment["HOMEBREW_NO_AUTO_UPDATE"] = "1"
        environment["NO_COLOR"] = "1"
        return environment
    }

    static func scan(environment: [String: String]) async -> [Installation] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let directories = (environment["PATH"] ?? "").split(separator: ":").map(String.init)
        var installs: [Installation] = []

        await withTaskGroup(of: [Installation].self) { group in
            for spec in ToolSpec.all where spec.id != "java" {
                group.addTask {
                    await find(spec, in: directories, environment: environment, home: home)
                }
            }
            group.addTask { await javaInstallations() }
            for await found in group { installs.append(contentsOf: found) }
        }
        return installs
    }

    private static func find(
        _ spec: ToolSpec, in directories: [String], environment: [String: String], home: String
    ) async -> [Installation] {
        var found: [Installation] = []
        var activeTarget: String?

        if let executable = directories.lazy.map({ "\($0)/\(spec.executable)" })
            .first(where: { FileManager.default.isExecutableFile(atPath: $0) })
        {
            let resolved = URL(fileURLWithPath: executable).resolvingSymlinksInPath().path
            activeTarget = resolved
            if let result = try? await ProcessRunner.run(
                executable, spec.versionArguments, environment: environment, timeout: 15),
                let version = parseVersion(spec, output: result.stdout, stderr: result.stderr)
            {
                found.append(
                    Installation(
                        toolID: spec.id, version: version, path: resolved,
                        source: InstallSource.of(path: resolved, home: home), isActive: true))
            }
        }

        // Side-by-side versions from version managers.
        for (relative, source) in spec.managedVersions {
            let folder = relative.replacingOccurrences(of: "~", with: home)
            guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder) else { continue }
            for name in names {
                let path = "\(folder)/\(name)"
                guard let version = Version(name),
                    !(activeTarget?.hasPrefix(path + "/") ?? false)  // already listed as the active one
                else { continue }
                found.append(
                    Installation(toolID: spec.id, version: version, path: path, source: source, isActive: false))
            }
        }
        return found
    }

    static func parseVersion(_ spec: ToolSpec, output: Data, stderr: String) -> Version? {
        let text = String(decoding: output, as: UTF8.self) + "\n" + stderr
        switch spec.id {
        case "swift":
            // "swift-driver version: 1.168.6 Apple Swift version 6.4 …" — the language version comes second.
            guard let range = text.range(of: #"Swift version \d+(\.\d+)*"#, options: .regularExpression) else {
                return nil
            }
            return Version(String(text[range]))
        case "go":
            guard let range = text.range(of: #"go\d+(\.\d+)*"#, options: .regularExpression) else { return nil }
            return Version(String(text[range]))
        default:
            return Version(text)
        }
    }

    /// Every installed JDK, from java_home (the /usr/bin/java stub exists even with none installed).
    private static func javaInstallations() async -> [Installation] {
        guard let list = try? await ProcessRunner.run("/usr/libexec/java_home", ["-X"], timeout: 10), list.succeeded,
            let entries = try? PropertyListSerialization.propertyList(from: list.stdout, format: nil)
                as? [[String: Any]]
        else { return [] }
        let defaultHome = (try? await ProcessRunner.run("/usr/libexec/java_home", [], timeout: 10))
            .map { String(decoding: $0.stdout, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) }
        return entries.compactMap { entry in
            guard let versionText = entry["JVMVersion"] as? String, let version = Version(versionText),
                let homePath = entry["JVMHomePath"] as? String
            else { return nil }
            return Installation(
                toolID: "java", version: version, path: homePath, source: .jdk, isActive: homePath == defaultHome,
                note: entry["JVMVendor"] as? String)
        }
    }
}

/// Public version lists. Only these fixed hosts are ever contacted, and nothing about this Mac is sent.
nonisolated enum VersionSources {
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.httpCookieAcceptPolicy = .never
        return URLSession(configuration: configuration)
    }()

    /// endoflife.date product for an installation (JDKs follow their vendor's schedule).
    static func lifecycleProduct(for install: Installation, spec: ToolSpec) -> String? {
        guard install.toolID == "java" else { return spec.lifecycleProduct }
        let vendor = (install.note ?? "").lowercased()
        if vendor.contains("azul") { return "azul-zulu" }
        if vendor.contains("amazon") { return "amazon-corretto" }
        if vendor.contains("oracle") { return "oracle-jdk" }
        if vendor.contains("microsoft") { return "microsoft-build-of-openjdk" }
        return "eclipse-temurin"
    }

    static func cycles(for product: String) async throws -> [ReleaseCycle] {
        guard product.range(of: #"^[a-z0-9-]+$"#, options: .regularExpression) != nil,
            let url = URL(string: "https://endoflife.date/api/\(product).json")
        else { throw URLError(.badURL) }
        let (data, response) = try await session.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode([ReleaseCycle].self, from: data)
    }

    /// Node releases nodejs.org marks as security fixes.
    static func nodeSecurityReleases() async throws -> [Version] {
        struct Release: Decodable {
            let version: String
            let security: Bool
        }
        let url = URL(string: "https://nodejs.org/dist/index.json")!
        let (data, _) = try await session.data(from: url)
        return try JSONDecoder().decode([Release].self, from: data).filter(\.security).compactMap {
            Version($0.version)
        }
    }

    nonisolated struct BrewOutdated: Identifiable, Sendable {
        let name: String
        let installed: String
        let current: String
        let isCask: Bool
        var id: String { (isCask ? "cask:" : "") + name }
        var command: String { isCask ? "brew upgrade --cask \(name)" : "brew upgrade \(name)" }
    }

    /// `brew outdated` against Homebrew's last downloaded index (no self-update).
    static func brewOutdated(environment: [String: String]) async -> [BrewOutdated] {
        let directories = (environment["PATH"] ?? "").split(separator: ":").map(String.init)
        guard
            let brew = directories.map({ "\($0)/brew" }).first(where: {
                FileManager.default.isExecutableFile(atPath: $0)
            }),
            let result = try? await ProcessRunner.run(
                brew, ["outdated", "--json=v2"], environment: environment, timeout: 60),
            let json = try? JSONSerialization.jsonObject(with: result.stdout) as? [String: Any]
        else { return [] }
        func items(_ key: String, cask: Bool) -> [BrewOutdated] {
            ((json[key] as? [[String: Any]]) ?? []).compactMap { item in
                guard let name = item["name"] as? String else { return nil }
                let installed = (item["installed_versions"] as? [String])?.last ?? "?"
                let current = item["current_version"] as? String ?? "?"
                return BrewOutdated(name: name, installed: installed, current: current, isCask: cask)
            }
        }
        return items("formulae", cask: false) + items("casks", cask: true)
    }
}

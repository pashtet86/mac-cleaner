import Foundation
import Testing

@testable import DevSpace

@Suite("SafeTrash policy")
struct SafeTrashTests {
    private let home = FileManager.default.homeDirectoryForCurrentUser

    @Test("Cache policy allows caches and refuses personal folders")
    func cachePolicy() {
        #expect(SafeTrash.isAllowed(home.appending(path: "Library/Caches/com.example"), policy: .caches))
        #expect(!SafeTrash.isAllowed(home.appending(path: "Documents/report.pdf"), policy: .caches))
        #expect(!SafeTrash.isAllowed(home.appending(path: "Desktop/screenshot.png"), policy: .caches))
    }

    @Test("User-files policy allows personal folders but never ~/Library")
    func userFilesPolicy() {
        #expect(SafeTrash.isAllowed(home.appending(path: "Documents/old.dmg"), policy: .userFiles))
        #expect(SafeTrash.isAllowed(home.appending(path: "Downloads/installer.pkg"), policy: .userFiles))
        #expect(!SafeTrash.isAllowed(home.appending(path: "Library/Preferences/x.plist"), policy: .userFiles))
    }

    @Test(
        "Always refuses system, sync and out-of-home locations",
        arguments: [SafeTrash.Policy.caches, .userFiles])
    func alwaysRefused(policy: SafeTrash.Policy) {
        #expect(!SafeTrash.isAllowed(home, policy: policy))
        #expect(!SafeTrash.isAllowed(home.appending(path: "Library/Keychains/login.keychain-db"), policy: policy))
        #expect(!SafeTrash.isAllowed(home.appending(path: "Library/CloudStorage/Drive/file"), policy: policy))
        #expect(!SafeTrash.isAllowed(home.appending(path: "Library/Mobile Documents/doc"), policy: policy))
        #expect(!SafeTrash.isAllowed(URL(fileURLWithPath: "/System/Library/Fonts"), policy: policy))
        #expect(!SafeTrash.isAllowed(URL(fileURLWithPath: "/Applications/Xcode.app"), policy: policy))
    }

    @Test(
        "Standard home folders themselves can never be trashed",
        arguments: [SafeTrash.Policy.caches, .userFiles])
    func standardFolders(policy: SafeTrash.Policy) {
        for folder in SafeTrash.standardHomeFolders {
            #expect(!SafeTrash.isAllowed(home.appending(path: folder), policy: policy), "\(folder)")
        }
        #expect(SafeTrash.isAllowed(home.appending(path: "Downloads/old.dmg"), policy: .userFiles))
    }

    @Test("Path traversal cannot escape the home folder")
    func traversal() {
        let escaped = home.appending(path: "Library/Caches/../../../../etc/hosts")
        #expect(!SafeTrash.isAllowed(escaped, policy: .userFiles))
    }
}

@Suite("Cleanup rules")
struct CleanupRuleTests {
    private let rules = CleanupRule.loadBundled()

    @Test("Bundled rules decode and have unique identifiers")
    func decodes() {
        #expect(!rules.isEmpty)
        #expect(Set(rules.map(\.id)).count == rules.count)
    }

    @Test("Every rule stays inside the home or temporary folder")
    func pathsAreScoped() {
        for rule in rules {
            for path in rule.paths {
                #expect(path.hasPrefix("~/") || path.hasPrefix("$TMPDIR"), "\(rule.id): \(path)")
                #expect(!path.contains(".."), "\(rule.id): \(path)")
            }
        }
    }

    @Test("Scanning never opens privacy-protected folders such as the Music cache")
    func skipsPrivacyProtectedFolders() throws {
        // Regression: listing ~/Library/Caches/com.apple.Music raised the "Media & Apple Music" prompt.
        let name = "CleanupRuleTests-\(UUID().uuidString)"
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: name)
        defer { try? FileManager.default.removeItem(at: root) }
        for folder in ["com.apple.Music", "com.apple.TV", "CloudKit", "com.example.app"] {
            let dir = root.appending(path: folder)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try Data(repeating: 1, count: 10_000).write(to: dir.appending(path: "cache.bin"))
        }
        let rule = CleanupRule(
            id: "test", section: .apps, title: "", detail: "", symbol: "", risk: .safe,
            paths: ["$TMPDIR/\(name)"], namePrefixes: nil, excludePrefixes: nil, closeApps: nil)

        #expect(CleanupScanner.scan(rule).map(\.name) == ["com.example.app"])
    }

    @Test("App Caches leaves macOS's own caches alone")
    func appCachesSkipAppleCaches() throws {
        let userCaches = try #require(rules.first { $0.id == "user-caches" })
        #expect(userCaches.excludePrefixes?.contains("com.apple.") == true)
    }

    @Test("No rule targets personal folders")
    func noPersonalFolders() {
        let personal = ["~/Documents", "~/Desktop", "~/Pictures", "~/Movies", "~/Music", "~/Downloads"]
        for rule in rules {
            for path in rule.paths {
                #expect(!personal.contains { path.hasPrefix($0) }, "\(rule.id): \(path)")
            }
        }
    }
}

@Suite("Parsing")
struct ParsingTests {
    @Test(
        "Docker decimal sizes",
        arguments: [
            ("0B", Int64(0)), ("12.5kB", 12_500), ("500MB", 500_000_000),
            ("1.234GB (50%)", 1_234_000_000), ("2TB", 2_000_000_000_000), ("garbage", 0),
        ])
    func dockerSize(text: String, bytes: Int64) {
        #expect(Docker.parseSize(text) == bytes)
    }

    @Test("Simulator runtime identifiers become readable names")
    func runtimeName() {
        let device = SimDevice(
            udid: "X", name: "iPhone", state: "Shutdown", isAvailable: true, dataPathSize: nil,
            lastUsedAt: nil, runtimeIdentifier: "com.apple.CoreSimulator.SimRuntime.iOS-27-1")
        #expect(device.runtimeName == "iOS 27.1")
    }
}

@MainActor
@Suite("CapacityBar")
struct CapacityBarTests {
    @Test("Tiny segments are widened to a dot without overflowing")
    func minimumWidth() {
        let widths = CapacityBar.widths(for: [0.6, 0.001, 0.2], total: 500, minimum: 8, gap: 2)
        #expect(widths[1] == 8)
        #expect(widths.reduce(0, +) <= 500 * 0.801)
        #expect(widths[0] > widths[2])
    }

    @Test("Proportions are kept when nothing is tiny")
    func proportional() {
        let widths = CapacityBar.widths(for: [0.5, 0.25], total: 400, minimum: 6, gap: 2)
        #expect(widths == [198, 98])
    }
}

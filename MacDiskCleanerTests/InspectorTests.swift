import Foundation
import Testing

@testable import MacDiskCleaner

@Suite("Treemap layout")
struct TreemapLayoutTests {
    @Test("Tiles fill the rectangle exactly, without overlapping or leaving it")
    func fillsRect() {
        let rect = CGRect(x: 0, y: 0, width: 600, height: 400)
        let values: [Double] = [500, 300, 120, 60, 15, 5]
        let tiles = Treemap.layout(values, in: rect)

        let area = tiles.reduce(0) { $0 + $1.width * $1.height }
        #expect(abs(area - rect.width * rect.height) < 0.5)
        for tile in tiles {
            #expect(rect.insetBy(dx: -0.01, dy: -0.01).contains(tile))
        }
        for (i, a) in tiles.enumerated() {
            for b in tiles[(i + 1)...] {
                let overlap = a.intersection(b)
                #expect(overlap.isNull || overlap.width * overlap.height < 0.01)
            }
        }
    }

    @Test("Area is proportional to value")
    func proportional() {
        let tiles = Treemap.layout([3, 1], in: CGRect(x: 0, y: 0, width: 400, height: 100))
        let ratio = (tiles[0].width * tiles[0].height) / (tiles[1].width * tiles[1].height)
        #expect(abs(ratio - 3) < 0.01)
    }

    @Test("Empty input or rect gives no tiles")
    func degenerate() {
        #expect(Treemap.layout([], in: CGRect(x: 0, y: 0, width: 10, height: 10)).isEmpty)
        #expect(Treemap.layout([1, 2], in: .zero).allSatisfy { $0 == .zero })
    }
}

@Suite("Safety classifier")
struct SafetyClassifierTests {
    private let home = URL(fileURLWithPath: "/Users/tester")
    private var classifier: SafetyClassifier { SafetyClassifier(rules: CleanupRule.loadBundled(), home: home) }

    private func verdict(
        _ relative: String, directory: Bool = true, siblings: Set<String> = [], parent: Verdict? = nil
    ) -> Verdict {
        let path = home.path + "/" + relative
        return classifier.classify(
            path: path, name: (path as NSString).lastPathComponent, isDirectory: directory, siblings: siblings,
            parent: parent)
    }

    @Test("Standard folders, the Trash and ~/Library app data are protected")
    func protected() {
        #expect(verdict("Documents").safety == .protected)
        #expect(verdict("Downloads").safety == .protected)
        #expect(verdict(".Trash").safety == .protected)
        #expect(verdict("Library/Application Support/SomeApp").safety == .protected)
    }

    @Test("A cleanup rule's folder is protected; its children take the rule's risk")
    func cleanupRules() {
        #expect(verdict("Library/Caches").safety == .protected)
        let cache = verdict("Library/Caches/com.example.app")
        #expect(cache.safety == .rebuildable)
        #expect(cache.fromCleanupRule)
        #expect(verdict("Library/Developer/Xcode/Archives/2026-01-01").safety == .review)
        #expect(verdict("Library/Caches/com.apple.Music").safety == .protected)
    }

    @Test("Project artifacts are recognised from their neighbours")
    func projectArtifacts() {
        #expect(verdict("dev/app/node_modules").safety == .rebuildable)
        #expect(verdict("dev/tool/target", siblings: ["Cargo.toml", "src"]).safety == .rebuildable)
        #expect(verdict("dev/notes/target", siblings: ["notes.txt"]).safety == .personal)
        #expect(verdict("dev/android/app/build", siblings: ["build.gradle"]).safety == .rebuildable)
        #expect(verdict("dev/web/dist", siblings: ["package.json"]).safety == .likelySafe)
    }

    @Test("Everything inside node_modules inherits its verdict")
    func inheritance() {
        let parent = verdict("dev/app/node_modules")
        #expect(verdict("dev/app/node_modules/react", parent: parent).safety == .rebuildable)
    }

    @Test("Installers are likely safe, archives need review, other files are yours")
    func files() {
        #expect(verdict("Downloads/Xcode.xip", directory: false).safety == .likelySafe)
        #expect(verdict("Downloads/backup.zip", directory: false).safety == .review)
        #expect(verdict("Desktop/report.pdf", directory: false).safety == .personal)
    }
}

@Suite("Inspector scanner")
struct InspectorScannerTests {
    @Test("Builds sizes bottom-up, folds small items and classifies artifacts")
    func buildsTree() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "InspectorTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let modules = root.appending(path: "app/node_modules/pkg")
        try FileManager.default.createDirectory(at: modules, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 2_000_000).write(to: modules.appending(path: "big.bin"))
        try Data(repeating: 1, count: 10_000).write(to: root.appending(path: "app/small.txt"))

        let tree = InspectorScanner.scan(
            root: root, classifier: SafetyClassifier(rules: []), progress: InspectorScanner.Progress())

        let app = try #require(tree.children.first { $0.name == "app" })
        let nodeModules = try #require(app.children.first { $0.name == "node_modules" })
        #expect(nodeModules.safety == .rebuildable)
        #expect(app.smallCount == 1)
        #expect(tree.size == app.size)
        #expect(app.size >= 2_000_000)
        #expect(nodeModules.url.path.hasSuffix("app/node_modules"))
    }

    @Test("Removing a node shrinks every ancestor")
    func removal() {
        let verdict = Verdict(safety: .personal, reason: "")
        let root = InspectorNode(name: "root", isDirectory: true, size: 30, verdict: verdict)
        let folder = InspectorNode(name: "folder", isDirectory: true, size: 30, verdict: verdict)
        let file = InspectorNode(name: "file", isDirectory: false, size: 20, verdict: verdict)
        folder.parent = root
        root.children = [folder]
        file.parent = folder
        folder.children = [file]

        file.removeFromParent()

        #expect(folder.size == 10)
        #expect(root.size == 10)
        #expect(folder.children.isEmpty)
    }
}

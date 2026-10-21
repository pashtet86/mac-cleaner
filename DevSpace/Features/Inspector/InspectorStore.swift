import AppKit
import Foundation
import Observation

@Observable
final class InspectorStore {
    enum Phase: Equatable { case idle, scanning, ready, cleaning }

    private(set) var phase: Phase = .idle
    private(set) var root: URL = FileManager.default.homeDirectoryForCurrentUser
    private(set) var tree: InspectorNode?
    /// Folders opened from the root, root first.
    private(set) var path: [InspectorNode] = []
    var focused: InspectorNode?
    private(set) var selected: [ObjectIdentifier: InspectorNode] = [:]
    private(set) var scannedFiles = 0
    private(set) var currentFolder = ""
    private(set) var lastReport: TrashReport?
    var errorMessage: String?

    private let classifier: SafetyClassifier
    private var scanTask: Task<Void, Never>?

    init(rules: [CleanupRule] = CleanupRule.loadBundled()) {
        classifier = SafetyClassifier(rules: rules)
    }

    var current: InspectorNode? { path.last ?? tree }
    var isScanning: Bool { phase == .scanning }

    // MARK: - Navigation

    func open(_ node: InspectorNode) {
        guard node.canOpen else { return }
        path.append(node)
        focused = nil
    }

    func goTo(depth: Int) {
        path = Array(path.prefix(depth + 1))
        focused = nil
    }

    func goUp() {
        guard path.count > 1 else { return }
        path.removeLast()
        focused = nil
    }

    // MARK: - Selection

    /// Selected itself or inside a selected folder.
    func isSelected(_ node: InspectorNode) -> Bool {
        selected[node.id] != nil || node.ancestors.contains { selected[$0.id] != nil }
    }

    func isCoveredByAncestor(_ node: InspectorNode) -> Bool {
        node.ancestors.contains { selected[$0.id] != nil }
    }

    func toggle(_ node: InspectorNode) {
        guard node.safety.isSelectable, !isCoveredByAncestor(node) else { return }
        if selected[node.id] != nil {
            selected[node.id] = nil
        } else {
            // A folder absorbs anything already selected inside it.
            selected = selected.filter { !$0.value.ancestors.contains { $0 === node } }
            selected[node.id] = node
        }
    }

    var selectedNodes: [InspectorNode] { selected.values.sorted { $0.size > $1.size } }
    var selectedBytes: Int64 { selected.values.reduce(0) { $0 + $1.size } }

    // MARK: - Scan

    func chooseRoot() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.directoryURL = root
        panel.prompt = "Inspect"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
        guard url.standardizedFileURL.path.hasPrefix(home) else {
            errorMessage = "Only folders inside your home folder can be inspected."
            return
        }
        root = url
        scan()
    }

    #if DEBUG
    func debugSetRoot(_ url: URL) { root = url }
    #endif

    func scan() {
        guard !isScanning else { return }
        let root = root
        let classifier = classifier
        let progress = InspectorScanner.Progress()
        phase = .scanning
        scannedFiles = 0
        lastReport = nil

        scanTask = Task {
            let work = Task.detached(priority: .userInitiated) {
                InspectorScanner.scan(root: root, classifier: classifier, progress: progress)
            }
            // Poll the counters instead of hopping to the main actor per folder.
            let poll = Task {
                while !Task.isCancelled {
                    scannedFiles = progress.files
                    currentFolder = progress.current
                    try? await Task.sleep(for: .milliseconds(200))
                }
            }
            let result = await withTaskCancellationHandler {
                await work.value
            } onCancel: {
                work.cancel()
            }
            poll.cancel()
            guard !Task.isCancelled else { return }
            scannedFiles = progress.files
            tree = result
            path = [result]
            focused = nil
            selected = [:]
            phase = .ready
        }
    }

    func cancel() {
        scanTask?.cancel()
        scanTask = nil
        phase = tree == nil ? .idle : .ready
    }

    // MARK: - Delete

    func trashSelected() async {
        let nodes = selectedNodes
        guard !nodes.isEmpty else { return }
        phase = .cleaning
        // Rule matches use the cache policy; everything else the stricter user-files policy.
        let byPolicy = Dictionary(grouping: nodes) { $0.verdict.fromCleanupRule }
        var report = TrashReport()
        for (fromRule, group) in byPolicy {
            let part = await SafeTrash.trash(
                group.map { (url: $0.url, size: $0.size) }, policy: fromRule ? .caches : .userFiles)
            report.movedCount += part.movedCount
            report.movedBytes += part.movedBytes
            report.failures += part.failures
        }
        for node in nodes where !FileManager.default.fileExists(atPath: node.url.path) {
            if focused === node { focused = nil }
            path.removeAll { $0 === node || $0.ancestors.contains { $0 === node } }
            node.removeFromParent()
        }
        if path.isEmpty, let tree { path = [tree] }
        selected = [:]
        lastReport = report
        phase = .ready
    }

    func dismissReport() { lastReport = nil }
}

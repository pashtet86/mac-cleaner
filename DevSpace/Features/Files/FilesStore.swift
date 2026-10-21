import AppKit
import Foundation
import Observation

/// One file scan. The Large Files and Duplicates pages each own an instance,
/// so a large-file scan never waits for hashing.
@Observable
final class FilesStore {
    enum Mode { case large, duplicates }

    enum Phase: Equatable {
        case idle
        case scanning(files: Int)
        case hashing(done: Int, total: Int)
        case ready
        case cleaning
    }

    enum SizeOption: Int64, Identifiable {
        case mb1 = 1_000_000
        case mb10 = 10_000_000
        case mb100 = 100_000_000
        case mb500 = 500_000_000
        case gb1 = 1_000_000_000
        var id: Int64 { rawValue }
        var label: String { rawValue.formattedBytes }
    }

    let mode: Mode
    private(set) var phase: Phase = .idle
    private(set) var roots: [URL] = [FileManager.default.homeDirectoryForCurrentUser]
    /// Large files: the size threshold. Duplicates: the smallest file worth hashing.
    var minimumSize: SizeOption
    private(set) var largeFiles: [FileEntry] = []
    private(set) var duplicateGroups: [DuplicateGroup] = []
    private(set) var scannedFiles = 0
    private(set) var scannedAt: Date?
    private(set) var lastReport: TrashReport?
    var selection: Set<URL> = []
    var errorMessage: String?

    private var scanTask: Task<Void, Never>?

    init(mode: Mode) {
        self.mode = mode
        minimumSize = mode == .large ? .mb500 : .mb1
    }

    var sizeOptions: [SizeOption] { mode == .large ? [.mb100, .mb500, .gb1] : [.mb1, .mb10, .mb100] }

    var isScanning: Bool {
        switch phase {
        case .scanning, .hashing: true
        default: false
        }
    }

    var largeBytes: Int64 { largeFiles.reduce(0) { $0 + $1.size } }
    var wastedBytes: Int64 { duplicateGroups.reduce(0) { $0 + $1.wasted } }

    func bytes(of kind: FileKind) -> Int64 {
        largeFiles.filter { $0.kind == kind }.reduce(0) { $0 + $1.size }
    }

    private var allEntries: [FileEntry] { mode == .large ? largeFiles : duplicateGroups.flatMap(\.files) }

    var selectedEntries: [FileEntry] { allEntries.filter { selection.contains($0.url) } }

    var selectedBytes: Int64 { selectedEntries.reduce(0) { $0 + $1.size } }

    /// Groups where every copy is selected — cleaning would lose the content.
    var fullySelectedGroups: [DuplicateGroup] {
        duplicateGroups.filter { group in group.files.allSatisfy { selection.contains($0.url) } }
    }

    func toggle(_ entry: FileEntry) {
        if selection.contains(entry.url) { selection.remove(entry.url) } else { selection.insert(entry.url) }
    }

    /// Selects every copy but the oldest in each group.
    func selectAllButOldest() {
        for group in duplicateGroups {
            selection.remove(group.files[0].url)
            selection.formUnion(group.files.dropFirst().map(\.url))
        }
    }

    // MARK: - Scope

    func addRoot() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
        panel.prompt = "Add"
        guard panel.runModal() == .OK else { return }
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
        for url in panel.urls {
            let path = url.standardizedFileURL.path
            // Results outside the home folder could not be moved to the Trash safely.
            guard path.hasPrefix(home) else {
                errorMessage = "Only folders inside your home folder can be scanned."
                continue
            }
            if !roots.contains(where: { path.hasPrefix($0.standardizedFileURL.path) }) {
                roots.removeAll { $0.standardizedFileURL.path.hasPrefix(path) }
                roots.append(url)
            }
        }
    }

    func removeRoot(_ url: URL) {
        roots.removeAll { $0 == url }
    }

    #if DEBUG
    func debugSetRoots(_ urls: [URL]) { roots = urls }
    #endif

    func resetRoots() {
        roots = [FileManager.default.homeDirectoryForCurrentUser]
    }

    // MARK: - Scan

    func scan() {
        guard !isScanning, !roots.isEmpty else { return }
        let roots = roots
        let mode = mode
        let largeThreshold = mode == .large ? minimumSize.rawValue : .max
        let duplicateThreshold = mode == .duplicates ? minimumSize.rawValue : .max
        phase = .scanning(files: 0)
        lastReport = nil

        scanTask = Task {
            let inventory = await cancellable {
                FileScanner.inventory(
                    roots: roots,
                    largeThreshold: largeThreshold,
                    duplicateThreshold: duplicateThreshold
                ) { count in
                    Task { @MainActor in
                        if case .scanning = self.phase { self.phase = .scanning(files: count) }
                    }
                }
            }
            guard !Task.isCancelled else { return }

            var groups: [DuplicateGroup] = []
            if mode == .duplicates {
                phase = .hashing(done: 0, total: inventory.sameSize.count)
                let candidates = inventory.sameSize
                groups = await cancellable {
                    await FileScanner.duplicates(in: candidates) { done, total in
                        Task { @MainActor in
                            if case .hashing = self.phase { self.phase = .hashing(done: done, total: total) }
                        }
                    }
                }
                guard !Task.isCancelled else { return }
            }

            largeFiles = inventory.large
            duplicateGroups = groups
            scannedFiles = inventory.scannedFiles
            scannedAt = .now
            selection = []
            phase = .ready
        }
    }

    /// Runs `work` off the main actor and forwards cancellation of the caller to it.
    private func cancellable<T: Sendable>(_ work: @escaping @Sendable () async -> T) async -> T {
        let task = Task.detached(priority: .userInitiated, operation: work)
        return await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
    }

    func cancel() {
        scanTask?.cancel()
        scanTask = nil
        phase = scannedAt == nil ? .idle : .ready
    }

    func trashSelected() async {
        let targets = selectedEntries.map { (url: $0.url, size: $0.size) }
        guard !targets.isEmpty else { return }
        phase = .cleaning
        let report = await SafeTrash.trash(targets, policy: .userFiles)
        let moved = Set(targets.map(\.url).filter { !FileManager.default.fileExists(atPath: $0.path) })
        largeFiles.removeAll { moved.contains($0.url) }
        duplicateGroups = duplicateGroups.compactMap { group in
            let files = group.files.filter { !moved.contains($0.url) }
            return files.count > 1 ? DuplicateGroup(id: group.id, size: group.size, files: files) : nil
        }
        selection.subtract(moved)
        lastReport = report
        phase = .ready
    }

    func dismissReport() { lastReport = nil }
}

/// Both file scans, injected into the environment as one object.
@Observable
final class FileScans {
    let large = FilesStore(mode: .large)
    let duplicates = FilesStore(mode: .duplicates)
}

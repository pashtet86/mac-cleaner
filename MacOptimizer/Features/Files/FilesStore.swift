import AppKit
import Foundation
import Observation

@Observable
final class FilesStore {
    enum Phase: Equatable {
        case idle
        case scanning(files: Int)
        case hashing(done: Int, total: Int)
        case ready
        case cleaning
    }

    enum Threshold: Int64, CaseIterable, Identifiable {
        case mb100 = 100_000_000
        case mb500 = 500_000_000
        case gb1 = 1_000_000_000
        var id: Int64 { rawValue }
        var label: String { rawValue.formattedBytes }
    }

    private(set) var phase: Phase = .idle
    private(set) var roots: [URL] = [FileManager.default.homeDirectoryForCurrentUser]
    var threshold: Threshold = .mb500
    private(set) var largeFiles: [FileEntry] = []
    private(set) var duplicateGroups: [DuplicateGroup] = []
    private(set) var scannedFiles = 0
    private(set) var scannedAt: Date?
    private(set) var lastReport: TrashReport?
    var selection: Set<URL> = []
    var errorMessage: String?

    /// Duplicates smaller than this are not worth the hashing time.
    private let duplicateThreshold: Int64 = 1_000_000
    private var scanTask: Task<Void, Never>?

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

    /// Every selected file, de-duplicated across both lists.
    var selectedEntries: [FileEntry] {
        var seen: Set<URL> = []
        return (largeFiles + duplicateGroups.flatMap(\.files)).filter {
            selection.contains($0.url) && seen.insert($0.url).inserted
        }
    }

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
        let largeThreshold = threshold.rawValue
        let duplicateThreshold = duplicateThreshold
        phase = .scanning(files: 0)
        lastReport = nil

        scanTask = Task {
            let inventory = await cancellable {
                FileScanner.inventory(
                    roots: roots, largeThreshold: largeThreshold,
                    duplicateThreshold: duplicateThreshold
                ) { count in
                    Task { @MainActor [weak self] in
                        if case .scanning = self?.phase { self?.phase = .scanning(files: count) }
                    }
                }
            }
            guard !Task.isCancelled else { return }

            phase = .hashing(done: 0, total: inventory.sameSize.count)
            let candidates = inventory.sameSize
            let groups = await cancellable {
                await FileScanner.duplicates(in: candidates) { done, total in
                    Task { @MainActor [weak self] in
                        if case .hashing = self?.phase { self?.phase = .hashing(done: done, total: total) }
                    }
                }
            }
            guard !Task.isCancelled else { return }

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
        let moved = Set(targets.map(\.url)).subtracting(
            targets.map(\.url).filter { FileManager.default.fileExists(atPath: $0.path) })
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

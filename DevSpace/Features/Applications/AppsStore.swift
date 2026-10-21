import AppKit
import Foundation
import Observation

@Observable
final class AppsStore {
    enum Sort: String, CaseIterable, Identifiable {
        case size = "Size"
        case lastUsed = "Last used"
        case name = "Name"
        var id: String { rawValue }
    }

    /// Apps not opened for this long are marked unused.
    static let unusedInterval: TimeInterval = 180 * 24 * 3600

    private(set) var apps: [AppEntry] = []
    private(set) var isLoading = false
    private(set) var hasLoaded = false
    private(set) var removing: Set<URL> = []
    var sort: Sort = .size
    var query = ""
    var errorMessage: String?

    var unusedCutoff: Date { Date().addingTimeInterval(-Self.unusedInterval) }

    var visibleApps: [AppEntry] {
        let filtered =
            query.isEmpty
            ? apps
            : apps.filter { $0.name.localizedCaseInsensitiveContains(query) || ($0.bundleID ?? "").contains(query) }
        switch sort {
        case .size: return filtered.sorted { ($0.size ?? -1) > ($1.size ?? -1) }
        case .lastUsed: return filtered.sorted { ($0.lastUsed ?? .distantPast) < ($1.lastUsed ?? .distantPast) }
        case .name: return filtered
        }
    }

    var totalBytes: Int64 { apps.reduce(0) { $0 + ($1.size ?? 0) } }
    var unusedApps: [AppEntry] { apps.filter { !$0.isSystem && $0.isUnused(after: unusedCutoff) } }
    var unusedBytes: Int64 { unusedApps.reduce(0) { $0 + ($1.size ?? 0) } }
    var isMeasuring: Bool { apps.contains { $0.size == nil } }

    func isRunning(_ app: AppEntry) -> Bool {
        NSWorkspace.shared.runningApplications.contains {
            $0.bundleURL?.standardizedFileURL == app.url.standardizedFileURL
        }
    }

    func refreshIfNeeded() async {
        if !hasLoaded { await refresh() }
    }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer {
            isLoading = false
            hasLoaded = true
        }
        apps = await Task.detached(priority: .userInitiated) { AppCatalog.list() }.value
        // Sizes stream in: big bundles like Xcode take seconds each.
        await withTaskGroup(of: (URL, Int64).self) { group in
            var pending = apps.map(\.url).makeIterator()
            for _ in 0..<4 {
                guard let url = pending.next() else { break }
                group.addTask(priority: .utility) { (url, DiskUsage.allocatedSize(of: url)) }
            }
            for await (url, size) in group {
                if let index = apps.firstIndex(where: { $0.url == url }) { apps[index].size = size }
                if let next = pending.next() {
                    group.addTask(priority: .utility) { (next, DiskUsage.allocatedSize(of: next)) }
                }
            }
        }
    }

    /// Moves the app to the Trash. Apps owned by root (App Store installs) go through Finder,
    /// which asks for an administrator password itself.
    func remove(_ app: AppEntry) async {
        guard !app.isSystem else { return }
        guard !isRunning(app) else {
            errorMessage = "Quit \(app.name) before removing it."
            return
        }
        removing.insert(app.url)
        defer { removing.remove(app.url) }
        do {
            try SafeTrash.trashApplication(app.url)
        } catch {
            guard SafeTrash.isRemovableApplication(app.url) else {
                errorMessage = "\(app.name) can't be removed from here."
                return
            }
            await removeWithFinder(app)
        }
        if !FileManager.default.fileExists(atPath: app.url.path) {
            apps.removeAll { $0.url == app.url }
        }
    }

    private func removeWithFinder(_ app: AppEntry) async {
        // The path is passed as an argument, never spliced into the script text.
        let script = [
            "on run argv",
            "tell application \"Finder\" to delete (POSIX file (item 1 of argv) as alias)",
            "end run",
        ]
        let arguments = script.flatMap { ["-e", $0] } + [app.url.path]
        do {
            try await ProcessRunner.checked("/usr/bin/osascript", arguments)
        } catch {
            errorMessage = "Couldn't remove \(app.name): \(error.localizedDescription)"
        }
    }
}

import Foundation

nonisolated struct TrashReport: Sendable {
    var movedCount = 0
    var movedBytes: Int64 = 0
    var failures: [String] = []
}

/// Moves items to the Trash, refusing anything outside the user's home or temp
/// directory, the roots themselves, and a deny list of sensitive locations.
nonisolated enum SafeTrash {
    enum Policy: Sendable {
        /// Cache rules: never touches personal folders such as Documents or Desktop.
        case caches
        /// Files the user picked one by one in a preview: personal folders are allowed,
        /// system and sync locations are not.
        case userFiles
    }

    private static var home: String {
        FileManager.default.homeDirectoryForCurrentUser.resolvingSymlinksInPath().standardizedFileURL.path
    }

    private static var temp: String {
        URL(fileURLWithPath: NSTemporaryDirectory()).resolvingSymlinksInPath().standardizedFileURL.path
    }

    private static let personalSubpaths = ["Documents", "Desktop", "Pictures", "Movies", "Music"]

    private static let systemSubpaths = [
        "Library/Keychains", "Library/Mail", "Library/Messages",
        "Library/CloudStorage", "Library/Mobile Documents",
    ]

    static func isAllowed(_ url: URL, policy: Policy = .caches) -> Bool {
        let path = url.resolvingSymlinksInPath().standardizedFileURL.path
        if path.split(separator: "/").contains(where: { DiskUsage.skippedNames.contains(String($0)) }) {
            return false
        }
        let home = home
        let denied = policy == .caches ? personalSubpaths + systemSubpaths : systemSubpaths + ["Library"]
        for denied in denied {
            let deniedPath = home + "/" + denied
            if path == deniedPath || path.hasPrefix(deniedPath + "/") { return false }
        }
        return [home, temp].contains { root in path.hasPrefix(root + "/") }
    }

    static func trash(_ items: [(url: URL, size: Int64)], policy: Policy = .caches) async -> TrashReport {
        await Task.detached(priority: .userInitiated) {
            var report = TrashReport()
            for item in items {
                guard isAllowed(item.url, policy: policy) else {
                    report.failures.append("\(item.url.lastPathComponent): outside allowed locations")
                    continue
                }
                do {
                    try FileManager.default.trashItem(at: item.url, resultingItemURL: nil)
                    report.movedCount += 1
                    report.movedBytes += item.size
                } catch {
                    report.failures.append("\(item.url.lastPathComponent): \(error.localizedDescription)")
                }
            }
            return report
        }.value
    }
}

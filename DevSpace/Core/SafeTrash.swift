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

    /// Applications may be removed only as whole `.app` bundles inside /Applications or
    /// ~/Applications (one subfolder deep, e.g. "/Applications/Adobe Photoshop/Photoshop.app").
    static func isRemovableApplication(_ url: URL) -> Bool {
        let path = url.resolvingSymlinksInPath().standardizedFileURL.path
        guard path.hasSuffix(".app") else { return false }
        for root in ["/Applications", home + "/Applications"] where path.hasPrefix(root + "/") {
            let relative = path.dropFirst(root.count + 1).split(separator: "/")
            // The bundle itself, never something inside it.
            return (1...2).contains(relative.count) && relative.dropLast().allSatisfy { !$0.hasSuffix(".app") }
        }
        return false
    }

    static func trashApplication(_ url: URL) throws {
        guard isRemovableApplication(url) else { throw CocoaError(.fileWriteNoPermission) }
        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
    }

    /// Standard home folders. They may hold removable items, but are never removed themselves.
    static let standardHomeFolders = [
        "Applications", "Desktop", "Documents", "Downloads", "Library", "Movies", "Music", "Pictures", "Public",
    ]

    static func isAllowed(_ url: URL, policy: Policy = .caches) -> Bool {
        let path = url.resolvingSymlinksInPath().standardizedFileURL.path
        if path.split(separator: "/").contains(where: { DiskUsage.skippedNames.contains(String($0)) }) {
            return false
        }
        let home = home
        if standardHomeFolders.contains(where: { path == home + "/" + $0 }) { return false }
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

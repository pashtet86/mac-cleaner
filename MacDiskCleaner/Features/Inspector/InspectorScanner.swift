import Foundation

/// Builds the size tree for the Files Inspector in one pass over the disk.
nonisolated enum InspectorScanner {
    /// Items smaller than this are summed into their parent instead of getting a node.
    static let keepThreshold: Int64 = 1_000_000

    /// Live counters read by the UI while a scan runs.
    final class Progress: @unchecked Sendable {
        private let lock = NSLock()
        private var _files = 0
        private var _current = ""

        var files: Int { lock.withLock { _files } }
        var current: String { lock.withLock { _current } }

        func add(files count: Int, in folder: String) {
            lock.withLock {
                _files += count
                _current = folder
            }
        }
    }

    private static let keys: [URLResourceKey] = [
        .isDirectoryKey, .isSymbolicLinkKey, .isPackageKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey,
    ]

    /// Never read: macOS guards them with privacy prompts, or they sync from the cloud.
    private static let protectedHomeSubpaths = [
        "Library/Containers", "Library/Group Containers", "Library/Mail", "Library/Messages",
        "Library/Safari", "Library/CloudStorage", "Library/Mobile Documents", "Library/Application Support/AddressBook",
        "Library/Application Support/CallHistoryDB", "Library/Calendars", "Library/HomeKit", "Music", "Movies/TV",
    ]

    private static let protectedPackageExtensions: Set<String> = ["photoslibrary", "musiclibrary", "tvlibrary"]

    static func scan(root: URL, classifier: SafetyClassifier, progress: Progress) -> InspectorNode {
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
        let skipped = Set(protectedHomeSubpaths.map { home + "/" + $0 })
        let rootPath = root.standardizedFileURL.path
        let verdict = classifier.classify(
            path: rootPath, name: root.lastPathComponent, isDirectory: true, siblings: [], parent: nil)
        let node = InspectorNode(name: root.lastPathComponent, isDirectory: true, size: 0, verdict: verdict)
        node.rootURL = root
        var notScanned: [String] = []
        fill(
            node, at: root, path: rootPath, depth: 0, classifier: classifier, skipped: skipped,
            progress: progress, notScanned: &notScanned)
        node.notScanned = notScanned
        return node
    }

    private struct Entry {
        let url: URL
        let name: String
        let isDirectory: Bool
        let isPackage: Bool
        let size: Int64
    }

    private static func fill(
        _ node: InspectorNode, at url: URL, path: String, depth: Int, classifier: SafetyClassifier,
        skipped: Set<String>, progress: Progress, notScanned: inout [String]
    ) {
        guard
            let urls = try? FileManager.default.contentsOfDirectory(
                at: url, includingPropertiesForKeys: keys, options: [])
        else { return }

        var entries: [Entry] = []
        for child in urls {
            guard let values = try? child.resourceValues(forKeys: Set(keys)), values.isSymbolicLink != true else {
                continue
            }
            let name = child.lastPathComponent
            let childPath = path + "/" + name
            let isDirectory = values.isDirectory == true
            let isPackage = values.isPackage == true
            if skipped.contains(childPath) || DiskUsage.skippedNames.contains(name)
                || DiskUsage.isPrivacyProtected(name)
                || (isPackage && protectedPackageExtensions.contains(child.pathExtension.lowercased()))
            {
                if isDirectory { notScanned.append(childPath) }
                continue
            }
            let size = isDirectory ? 0 : Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
            entries.append(Entry(url: child, name: name, isDirectory: isDirectory, isPackage: isPackage, size: size))
        }
        let siblings = Set(entries.map(\.name))
        progress.add(files: entries.count(where: { !$0.isDirectory }), in: folderName(of: path))

        // Children are independent subtrees: build the top levels in parallel,
        // each task writing only its own result slot.
        let parentVerdict = node.verdict
        let compute = { (index: Int) -> (node: InspectorNode, skips: [String])? in
            if Task.isCancelled { return nil }
            let entry = entries[index]
            let childPath = path + "/" + entry.name
            let isFolder = entry.isDirectory && !entry.isPackage
            let verdict = classifier.classify(
                path: childPath, name: entry.name, isDirectory: isFolder, siblings: siblings, parent: parentVerdict)
            guard isFolder else {
                let size = entry.isPackage ? DiskUsage.allocatedSize(of: entry.url) : entry.size
                return (InspectorNode(name: entry.name, isDirectory: false, size: size, verdict: verdict), [])
            }
            let child = InspectorNode(name: entry.name, isDirectory: true, size: 0, verdict: verdict)
            var skips: [String] = []
            fill(
                child, at: entry.url, path: childPath, depth: depth + 1, classifier: classifier,
                skipped: skipped, progress: progress, notScanned: &skips)
            return (child, skips)
        }

        var results = [(node: InspectorNode, skips: [String])?](repeating: nil, count: entries.count)
        if depth < 2, entries.count > 1 {
            results.withUnsafeMutableBufferPointer { buffer in
                let slots = ResultSlots(buffer: buffer)
                DispatchQueue.concurrentPerform(iterations: entries.count) { index in
                    slots.buffer[index] = compute(index)
                }
            }
        } else {
            for index in entries.indices { results[index] = compute(index) }
        }

        for result in results {
            guard let (child, skips) = result else { continue }
            notScanned.append(contentsOf: skips)
            node.size += child.size
            if child.size >= keepThreshold {
                child.parent = node
                node.children.append(child)
            } else {
                node.smallBytes += child.size
                node.smallCount += 1
            }
        }
        node.children.sort { $0.size > $1.size }
    }

    private static func folderName(of path: String) -> String { (path as NSString).lastPathComponent }
}

/// Lets `concurrentPerform` write each result into its own slot — no slot is shared.
private struct ResultSlots: @unchecked Sendable {
    let buffer: UnsafeMutableBufferPointer<(node: InspectorNode, skips: [String])?>
}

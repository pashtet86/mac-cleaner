import CryptoKit
import Foundation

nonisolated enum FileKind: String, CaseIterable, Sendable {
    case video, diskImage, archive, other

    var label: String {
        switch self {
        case .video: "Video"
        case .diskImage: "Installers & disk images"
        case .archive: "Archives"
        case .other: "Other"
        }
    }

    static func of(_ url: URL) -> FileKind {
        let name = url.lastPathComponent.lowercased()
        switch url.pathExtension.lowercased() {
        case "mov", "mp4", "m4v", "mkv", "avi", "webm", "prores": return .video
        case "dmg", "pkg", "iso", "xip", "img", "sparseimage", "sparsebundle", "vmdk", "qcow2", "ipa", "apk", "aab":
            return .diskImage
        case "zip", "rar", "7z", "tar", "tgz", "gz", "bz2", "xz", "zst": return .archive
        default: return name.hasSuffix(".tar.gz") ? .archive : .other
        }
    }
}

nonisolated struct FileEntry: Identifiable, Hashable, Sendable {
    let url: URL
    let size: Int64
    let modified: Date?
    var id: URL { url }
    var kind: FileKind { FileKind.of(url) }

    var displayPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let parent = url.deletingLastPathComponent().path
        return parent.hasPrefix(home) ? "~" + parent.dropFirst(home.count) : parent
    }
}

nonisolated struct DuplicateGroup: Identifiable, Hashable, Sendable {
    let id: String  // SHA-256 of the content
    let size: Int64
    let files: [FileEntry]
    var wasted: Int64 { size * Int64(files.count - 1) }
}

nonisolated enum FileScanner {
    /// Folder names never descended into: dependency trees and caches other modules own.
    static let skippedFolderNames: Set<String> = [
        "node_modules", "Pods", "DerivedData", "CloudStorage", "Mobile Documents",
    ]

    struct Inventory: Sendable {
        var large: [FileEntry] = []
        /// Files of identical size — the only possible duplicates.
        var sameSize: [[FileEntry]] = []
        var scannedFiles = 0
    }

    /// Walks `roots` once, collecting files ≥ `largeThreshold` and same-size
    /// candidates ≥ `duplicateThreshold`. Calls `progress` with the running file count.
    static func inventory(
        roots: [URL], largeThreshold: Int64, duplicateThreshold: Int64,
        progress: @Sendable (Int) -> Void
    ) -> Inventory {
        let keys: [URLResourceKey] = [
            .isRegularFileKey, .isDirectoryKey, .fileSizeKey, .totalFileAllocatedSizeKey,
            .contentModificationDateKey, .fileIdentifierKey,
        ]
        let library = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library").standardizedFileURL
            .path
        var inventory = Inventory()
        var bySize: [Int64: [FileEntry]] = [:]
        var seenInodes: Set<UInt64> = []

        for root in roots {
            guard
                let enumerator = FileManager.default.enumerator(
                    at: root, includingPropertiesForKeys: keys,
                    options: [.skipsHiddenFiles, .skipsPackageDescendants],
                    errorHandler: { _, _ in true }
                )
            else { continue }

            while let url = enumerator.nextObject() as? URL {
                if Task.isCancelled { return inventory }
                guard let values = try? url.resourceValues(forKeys: Set(keys)) else { continue }
                if values.isDirectory == true {
                    if skippedFolderNames.contains(url.lastPathComponent) || url.standardizedFileURL.path == library {
                        enumerator.skipDescendants()
                    }
                    continue
                }
                guard values.isRegularFile == true else { continue }
                // Hard links to one file are one file.
                if let inode = values.fileIdentifier, !seenInodes.insert(inode).inserted { continue }

                inventory.scannedFiles += 1
                if inventory.scannedFiles % 2_000 == 0 { progress(inventory.scannedFiles) }

                let size = Int64(values.fileSize ?? 0)
                let entry = FileEntry(
                    url: url, size: Int64(values.totalFileAllocatedSize ?? Int(size)),
                    modified: values.contentModificationDate)
                if entry.size >= largeThreshold { inventory.large.append(entry) }
                if size >= duplicateThreshold { bySize[size, default: []].append(entry) }
            }
        }
        progress(inventory.scannedFiles)
        inventory.large.sort { $0.size > $1.size }
        inventory.sameSize = bySize.values.filter { $0.count > 1 }
        return inventory
    }

    /// Narrows same-size candidates to byte-identical groups:
    /// head+tail sample hash first, full SHA-256 only for sample matches.
    static func duplicates(
        in candidates: [[FileEntry]], progress: @escaping @Sendable (Int, Int) -> Void
    ) async -> [DuplicateGroup] {
        let total = candidates.count
        var groups: [DuplicateGroup] = []
        var done = 0
        await withTaskGroup(of: [DuplicateGroup].self) { taskGroup in
            var iterator = candidates.makeIterator()
            // Bounded parallelism keeps the disk busy without thrashing it.
            for _ in 0..<4 {
                guard let next = iterator.next() else { break }
                taskGroup.addTask { resolve(next) }
            }
            for await found in taskGroup {
                groups.append(contentsOf: found)
                done += 1
                progress(done, total)
                if Task.isCancelled {
                    taskGroup.cancelAll()
                    break
                }
                if let next = iterator.next() { taskGroup.addTask { resolve(next) } }
            }
        }
        return groups.sorted { $0.wasted > $1.wasted }
    }

    private static func resolve(_ sameSize: [FileEntry]) -> [DuplicateGroup] {
        let bySample = Dictionary(grouping: sameSize) { sampleHash(of: $0.url) ?? UUID().uuidString }
            .values.filter { $0.count > 1 }
        var result: [DuplicateGroup] = []
        for candidates in bySample {
            if Task.isCancelled { return result }
            let byContent = Dictionary(grouping: candidates) { fullHash(of: $0.url) ?? UUID().uuidString }
            for (hash, files) in byContent where files.count > 1 {
                let ordered = files.sorted { ($0.modified ?? .distantFuture) < ($1.modified ?? .distantFuture) }
                result.append(DuplicateGroup(id: hash, size: ordered[0].size, files: ordered))
            }
        }
        return result
    }

    private static let sampleLength = 64 * 1024

    private static func sampleHash(of url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        guard let head = try? handle.read(upToCount: sampleLength) else { return nil }
        hasher.update(data: head)
        if let end = try? handle.seekToEnd(), end > UInt64(sampleLength * 2) {
            try? handle.seek(toOffset: end - UInt64(sampleLength))
            if let tail = try? handle.read(upToCount: sampleLength) { hasher.update(data: tail) }
        }
        return hasher.finalize().hex
    }

    private static func fullHash(of url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            if Task.isCancelled { return nil }
            // At end of file `read` returns nil (or empty data); only a throw is a failure.
            guard let chunk = try? handle.read(upToCount: 1 << 20) as Data?? else { return nil }
            guard let chunk, !chunk.isEmpty else { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().hex
    }
}

private extension SHA256.Digest {
    nonisolated var hex: String { map { String(format: "%02x", $0) }.joined() }
}

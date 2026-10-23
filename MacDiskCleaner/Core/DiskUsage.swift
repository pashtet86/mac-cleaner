import Foundation

nonisolated enum DiskUsage {
    /// Folders never traversed: reading online-only files triggers downloads or hangs.
    static let skippedNames: Set<String> = ["CloudStorage", "Mobile Documents"]

    /// Folders guarded by macOS privacy controls (TCC). Merely listing them raises a
    /// permission prompt — e.g. `com.apple.Music` asks for "Media & Apple Music" access —
    /// and they only hold system-managed data, so nothing ever reads them.
    static let privacyProtectedPrefixes = [
        "com.apple.Music", "com.apple.TV", "com.apple.HomeKit", "com.apple.homed", "com.apple.Safari",
        "com.apple.findmy", "com.apple.ap.adprivacyd", "com.apple.containermanagerd",
        "CloudKit", "FamilyCircle", "familycircled",
    ]

    static func isPrivacyProtected(_ name: String) -> Bool {
        privacyProtectedPrefixes.contains { name.hasPrefix($0) }
    }

    private static let keys: Set<URLResourceKey> = [
        .isDirectoryKey, .isSymbolicLinkKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey,
    ]

    /// Allocated on-disk size of a file or directory tree. Symlinks are not followed.
    static func allocatedSize(of url: URL) -> Int64 {
        guard let values = try? url.resourceValues(forKeys: keys) else { return 0 }
        if values.isSymbolicLink == true { return 0 }
        guard values.isDirectory == true else { return fileSize(values) }

        guard
            let enumerator = FileManager.default.enumerator(
                at: url,
                includingPropertiesForKeys: Array(keys),
                options: [],
                errorHandler: { _, _ in true }
            )
        else { return 0 }

        var total: Int64 = 0
        while let child = enumerator.nextObject() as? URL {
            if Task.isCancelled { break }
            if skippedNames.contains(child.lastPathComponent) || isPrivacyProtected(child.lastPathComponent) {
                enumerator.skipDescendants()
                continue
            }
            guard let childValues = try? child.resourceValues(forKeys: keys),
                childValues.isDirectory != true
            else { continue }
            total += fileSize(childValues)
        }
        return total
    }

    private static func fileSize(_ values: URLResourceValues) -> Int64 {
        Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
    }

    struct Volume: Sendable {
        let total: Int64
        let available: Int64
        var used: Int64 { total - available }
    }

    static func bootVolume() -> Volume? {
        let url = URL(fileURLWithPath: "/")
        guard
            let values = try? url.resourceValues(forKeys: [
                .volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey,
            ]),
            let total = values.volumeTotalCapacity,
            let available = values.volumeAvailableCapacityForImportantUsage
        else { return nil }
        return Volume(total: Int64(total), available: available)
    }
}

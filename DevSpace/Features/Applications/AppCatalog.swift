import CoreServices
import Foundation

nonisolated struct AppEntry: Identifiable, Hashable, Sendable {
    let url: URL
    let name: String
    let bundleID: String?
    let version: String?
    let lastUsed: Date?
    let isFromAppStore: Bool
    /// Account that owns the bundle, i.e. who installed it ("root" for App Store and installer packages).
    var owner: String? = nil
    var size: Int64?

    var id: URL { url }

    /// Ships with macOS (Safari, …) and can't be removed: Apple bundle ID without an App Store receipt.
    /// Xcode and other developer tools stay removable.
    var isSystem: Bool {
        guard let bundleID, bundleID.hasPrefix("com.apple.") else { return false }
        return !isFromAppStore && !bundleID.hasPrefix("com.apple.dt.")
    }

    func isUnused(after cutoff: Date) -> Bool {
        lastUsed.map { $0 < cutoff } ?? false
    }
}

/// Finds installed apps and reads their metadata. Sizes are computed separately (slow).
nonisolated enum AppCatalog {
    static var roots: [URL] {
        [
            URL(fileURLWithPath: "/Applications"),
            FileManager.default.homeDirectoryForCurrentUser.appending(path: "Applications"),
        ]
    }

    static func list() -> [AppEntry] {
        var seen: Set<String> = []
        var apps: [AppEntry] = []
        for root in roots {
            for url in bundles(in: root, depth: 0) where seen.insert(url.standardizedFileURL.path).inserted {
                apps.append(entry(for: url))
            }
        }
        return apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// `.app` bundles at the top level and one folder down (vendor folders like "Adobe Photoshop 2025").
    private static func bundles(in folder: URL, depth: Int) -> [URL] {
        guard
            let children = try? FileManager.default.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles])
        else { return [] }
        return children.flatMap { child -> [URL] in
            let values = try? child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values?.isSymbolicLink != true, values?.isDirectory == true else { return [] }
            if child.pathExtension == "app" { return [child] }
            return depth == 0 ? bundles(in: child, depth: 1) : []
        }
    }

    private static func entry(for url: URL) -> AppEntry {
        let info = Bundle(url: url)?.infoDictionary
        let name = FileManager.default.displayName(atPath: url.path)
        return AppEntry(
            url: url,
            name: name.hasSuffix(".app") ? String(name.dropLast(4)) : name,
            bundleID: info?["CFBundleIdentifier"] as? String,
            version: info?["CFBundleShortVersionString"] as? String,
            lastUsed: lastUsedDate(of: url),
            isFromAppStore: FileManager.default.fileExists(atPath: url.appending(path: "Contents/_MASReceipt").path),
            owner: (try? FileManager.default.attributesOfItem(atPath: url.path))?[.ownerAccountName] as? String
        )
    }

    /// Login accounts on this Mac: regular UIDs (501+) with a real shell, so service accounts don't count.
    static func humanAccounts() -> [String] {
        var names: [String] = []
        setpwent()
        defer { endpwent() }
        while let entry = getpwent() {
            let shell = String(cString: entry.pointee.pw_shell)
            guard entry.pointee.pw_uid >= 501, !shell.hasSuffix("false"), !shell.hasSuffix("nologin") else { continue }
            names.append(String(cString: entry.pointee.pw_name))
        }
        return names
    }

    /// "Anna Smith" from the account's full-name field, or the account name itself.
    static func fullName(of account: String) -> String {
        guard let entry = getpwnam(account), let gecos = entry.pointee.pw_gecos else { return account }
        let name = String(cString: gecos).split(separator: ",").first.map(String.init) ?? ""
        return name.isEmpty ? account : name
    }

    /// When the app was last opened, as recorded by Spotlight. Nil if never or Spotlight is off.
    private static func lastUsedDate(of url: URL) -> Date? {
        guard let item = MDItemCreateWithURL(kCFAllocatorDefault, url as CFURL) else { return nil }
        return MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date
    }
}

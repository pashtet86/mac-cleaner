import Foundation
import SwiftUI

nonisolated enum Risk: String, Codable, Sendable, CaseIterable {
    case safe, probablySafe, review

    var label: String {
        switch self {
        case .safe: "Safe"
        case .probablySafe: "Likely safe"
        case .review: "Review"
        }
    }
}

extension Risk {
    var tone: Color {
        switch self {
        case .safe: Theme.sage
        case .probablySafe: Theme.sand
        case .review: Theme.clay
        }
    }
}

/// Which sidebar page a rule belongs to.
nonisolated enum RuleSection: String, Codable, Sendable {
    case apps, xcode, ides, packages
}

nonisolated struct CleanupRule: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let section: RuleSection
    let title: String
    let detail: String
    let symbol: String
    let risk: Risk
    let paths: [String]
    /// When set, only children whose names start with one of these prefixes are cleaned.
    let namePrefixes: [String]?
    /// Children whose names start with these prefixes are skipped because
    /// another rule owns them (avoids double counting).
    let excludePrefixes: [String]?
    /// Bundle identifiers that should be quit before cleaning.
    let closeApps: [String]?

    var resolvedURLs: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let temp = NSTemporaryDirectory()
        return paths.map { raw in
            var path = raw
            if path.hasPrefix("~/") { path = home + path.dropFirst(1) }
            if path.hasPrefix("$TMPDIR") { path = temp + path.dropFirst("$TMPDIR".count) }
            return URL(fileURLWithPath: path).standardizedFileURL
        }
    }

    static func loadBundled() -> [CleanupRule] {
        guard let url = Bundle.main.url(forResource: "cleanup_rules", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let rules = try? JSONDecoder().decode([CleanupRule].self, from: data)
        else {
            assertionFailure("cleanup_rules.json missing or invalid")
            return []
        }
        return rules
    }
}

nonisolated struct CleanupItem: Identifiable, Hashable, Sendable {
    let url: URL
    let size: Int64
    var id: URL { url }
    var name: String { url.lastPathComponent }
}

nonisolated enum CleanupScanner {
    /// Lists the cleanable children of a rule's folders with their sizes, largest first.
    static func scan(_ rule: CleanupRule) -> [CleanupItem] {
        var items: [CleanupItem] = []
        for root in rule.resolvedURLs {
            guard
                let children = try? FileManager.default.contentsOfDirectory(
                    at: root, includingPropertiesForKeys: [.isSymbolicLinkKey], options: []
                )
            else { continue }
            for child in children {
                if Task.isCancelled { return items }
                if let prefixes = rule.namePrefixes,
                    !prefixes.contains(where: { child.lastPathComponent.hasPrefix($0) })
                {
                    continue
                }
                if rule.excludePrefixes?.contains(where: { child.lastPathComponent.hasPrefix($0) }) == true { continue }
                if DiskUsage.isPrivacyProtected(child.lastPathComponent) { continue }
                guard SafeTrash.isAllowed(child) else { continue }
                let size = DiskUsage.allocatedSize(of: child)
                // Empty folders and zero-byte files free nothing; leave them alone.
                if size > 0 { items.append(CleanupItem(url: child, size: size)) }
            }
        }
        return items.sorted { $0.size > $1.size }
    }
}

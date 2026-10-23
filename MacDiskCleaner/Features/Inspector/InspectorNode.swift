import Foundation
import SwiftUI

/// How safe an item is to delete, shown as the tile color in the Files Inspector.
nonisolated enum Safety: Int, CaseIterable, Sendable {
    case rebuildable, likelySafe, review, personal, protected

    var label: String {
        switch self {
        case .rebuildable: "Rebuildable"
        case .likelySafe: "Likely safe"
        case .review: "Review"
        case .personal: "Your files"
        case .protected: "Protected"
        }
    }

    var isSelectable: Bool { self != .protected }
}

extension Safety {
    var tone: Color {
        switch self {
        case .rebuildable: Theme.cleanable
        case .likelySafe: Theme.sand
        case .review: Theme.clay
        case .personal: Theme.slate
        case .protected: Theme.dataOther
        }
    }
}

/// Why an item got its safety level.
nonisolated struct Verdict: Sendable {
    let safety: Safety
    let reason: String
    /// Matched a cleanup rule: deleted with the cache policy rather than the user-files one.
    var fromCleanupRule = false
    /// Descendants share the verdict (everything inside node_modules is rebuildable too).
    var inheritable = false
}

/// One file or folder in the inspected tree. Items under `InspectorScanner.keepThreshold`
/// are folded into their parent's `smallBytes` to keep the tree small.
nonisolated final class InspectorNode: Identifiable, @unchecked Sendable {
    let name: String
    let isDirectory: Bool
    let verdict: Verdict
    var size: Int64
    var children: [InspectorNode] = []
    var smallBytes: Int64 = 0
    var smallCount = 0
    weak var parent: InspectorNode?
    /// Only set on the root.
    var rootURL: URL?
    /// Protected folders that were deliberately not read (root only).
    var notScanned: [String] = []

    private var breakdownCache: [Safety: Int64]?

    init(name: String, isDirectory: Bool, size: Int64, verdict: Verdict) {
        self.name = name
        self.isDirectory = isDirectory
        self.size = size
        self.verdict = verdict
    }

    var id: ObjectIdentifier { ObjectIdentifier(self) }
    var safety: Safety { verdict.safety }

    var url: URL {
        if let rootURL { return rootURL }
        guard let parent else { return URL(fileURLWithPath: name) }
        return parent.url.appending(path: name, directoryHint: isDirectory ? .isDirectory : .notDirectory)
    }

    var ancestors: [InspectorNode] {
        var chain: [InspectorNode] = []
        var node = parent
        while let current = node {
            chain.append(current)
            node = current.parent
        }
        return chain
    }

    var canOpen: Bool { isDirectory && !children.isEmpty }

    /// The color a tile shows: what most of the bytes inside are. A project folder that is
    /// 90% node_modules reads as rebuildable at a glance; the folder's own verdict stays in the details.
    var displaySafety: Safety {
        guard isDirectory, !children.isEmpty else { return safety }
        return breakdown.max { $0.value < $1.value }?.key ?? safety
    }

    /// Bytes inside this node by safety level, counting every leaf with its own verdict.
    var breakdown: [Safety: Int64] {
        if let breakdownCache { return breakdownCache }
        var result: [Safety: Int64] = [:]
        if children.isEmpty {
            result[safety] = size
        } else {
            result[safety, default: 0] += smallBytes
            for child in children {
                for (key, value) in child.breakdown { result[key, default: 0] += value }
            }
        }
        breakdownCache = result
        return result
    }

    /// Detaches the node and shrinks every ancestor by its size.
    func removeFromParent() {
        guard let parent else { return }
        parent.children.removeAll { $0 === self }
        for ancestor in [parent] + parent.ancestors {
            ancestor.size -= size
            ancestor.breakdownCache = nil
        }
        self.parent = nil
    }
}

#if DEBUG
import AppKit
import SwiftUI

/// Debug-only: `DevSpace -snapshotDir <path>` renders each section of the
/// window to PNG in-process (no Screen Recording permission needed), then quits.
enum DebugSnapshot {
    static var directory: URL? {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "-snapshotDir"), args.indices.contains(index + 1) else { return nil }
        return URL(fileURLWithPath: args[index + 1], isDirectory: true)
    }

    /// `-snapshotFilesRoot <path>` scans that folder (instead of Home) in the Files Inspector, Large Files and Duplicates.
    static var filesRoot: URL? {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "-snapshotFilesRoot"), args.indices.contains(index + 1) else {
            return nil
        }
        return URL(fileURLWithPath: args[index + 1], isDirectory: true)
    }

    static func run(select: (AppSection) -> Void, files: FileScans, inspector: InspectorStore) async {
        guard let directory else { return }
        if let root = filesRoot {
            inspector.debugSetRoot(root)
            inspector.scan()
            while inspector.isScanning { try? await Task.sleep(for: .milliseconds(300)) }
            inspector.focused = inspector.tree?.children.first
            for store in [files.large, files.duplicates] {
                store.debugSetRoots([root])
                store.scan()
                while store.isScanning { try? await Task.sleep(for: .milliseconds(300)) }
            }
            files.duplicates.selectAllButOldest()
        }
        // `-snapshotSize 860x640` checks layouts at small window sizes.
        let args = ProcessInfo.processInfo.arguments
        if let index = args.firstIndex(of: "-snapshotSize"), args.indices.contains(index + 1) {
            let parts = args[index + 1].split(separator: "x").compactMap { Double($0) }
            if parts.count == 2, let window = NSApp.windows.first(where: \.isVisible) {
                try? await Task.sleep(for: .seconds(1))
                var frame = window.frame
                frame.size =
                    window.frameRect(forContentRect: NSRect(x: 0, y: 0, width: parts[0], height: parts[1])).size
                window.setFrame(frame, display: true)
            }
        }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            NSApp.appearance = NSAppearance(named: appearance)
            for section in AppSection.available {
                select(section)
                try? await Task.sleep(for: .seconds(section == .overview ? 6 : 3))
                let suffix = appearance == .darkAqua ? "dark" : "light"
                capture(to: directory.appending(path: "\(section.rawValue)-\(suffix).png"))
            }
        }
        NSApp.terminate(nil)
    }

    private static func capture(to url: URL) {
        guard let view = NSApp.windows.first(where: \.isVisible)?.contentView?.superview,
            let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)
        else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}
#endif

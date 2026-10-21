#if DEBUG
import AppKit
import SwiftUI

/// Debug-only: `MacOptimizer -snapshotDir <path>` renders each section of the
/// window to PNG in-process (no Screen Recording permission needed), then quits.
enum DebugSnapshot {
    static var directory: URL? {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "-snapshotDir"), args.indices.contains(index + 1) else { return nil }
        return URL(fileURLWithPath: args[index + 1], isDirectory: true)
    }

    /// `-snapshotFilesRoot <path>` scans that folder (instead of Home) for the Files page.
    static var filesRoot: URL? {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "-snapshotFilesRoot"), args.indices.contains(index + 1) else {
            return nil
        }
        return URL(fileURLWithPath: args[index + 1], isDirectory: true)
    }

    static func run(select: (AppSection) -> Void, files: FilesStore) async {
        guard let directory else { return }
        if let root = filesRoot {
            files.debugSetRoots([root])
            files.scan()
            while files.isScanning { try? await Task.sleep(for: .milliseconds(300)) }
            files.selectAllButOldest()
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

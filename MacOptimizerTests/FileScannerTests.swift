import Foundation
import Testing

@testable import MacOptimizer

@Suite("FileScanner")
struct FileScannerTests {
    /// A throwaway folder, removed when the test ends.
    final class Sandbox {
        let url: URL

        init() throws {
            url = FileManager.default.temporaryDirectory.appending(path: "FileScannerTests-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }

        deinit { try? FileManager.default.removeItem(at: url) }

        @discardableResult
        func file(_ path: String, bytes: Int, seed: UInt8 = 1) throws -> URL {
            let target = url.appending(path: path)
            try FileManager.default.createDirectory(
                at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = Data((0..<bytes).map { UInt8(truncatingIfNeeded: $0) &+ seed })
            try data.write(to: target)
            return target
        }
    }

    private func duplicates(in root: URL, minimum: Int64 = 1) async -> [DuplicateGroup] {
        let inventory = FileScanner.inventory(
            roots: [root], largeThreshold: .max, duplicateThreshold: minimum, progress: { _ in })
        return await FileScanner.duplicates(in: inventory.sameSize, progress: { _, _ in })
    }

    @Test("Finds byte-identical files whose size is not a multiple of the read chunk")
    func findsDuplicatesAcrossEndOfFile() async throws {
        // Regression: reading past EOF returns nil, which used to abort the full hash.
        let sandbox = try Sandbox()
        try sandbox.file("a/copy.bin", bytes: 300_001)
        try sandbox.file("b/copy.bin", bytes: 300_001)

        let groups = await duplicates(in: sandbox.url)

        #expect(groups.count == 1)
        #expect(groups.first?.files.count == 2)
    }

    @Test("Same size with different content is not a duplicate")
    func sameSizeDifferentContent() async throws {
        let sandbox = try Sandbox()
        try sandbox.file("one.bin", bytes: 200_000, seed: 1)
        try sandbox.file("two.bin", bytes: 200_000, seed: 2)

        #expect(await duplicates(in: sandbox.url).isEmpty)
    }

    @Test("Hard links to one file are counted once")
    func hardLinksAreNotDuplicates() async throws {
        let sandbox = try Sandbox()
        let original = try sandbox.file("original.bin", bytes: 100_000)
        try FileManager.default.linkItem(at: original, to: sandbox.url.appending(path: "link.bin"))

        #expect(await duplicates(in: sandbox.url).isEmpty)
    }

    @Test("Skips dependency folders such as node_modules")
    func skipsNodeModules() async throws {
        let sandbox = try Sandbox()
        try sandbox.file("app/node_modules/pkg/big.bin", bytes: 50_000)
        try sandbox.file("app/src/big.bin", bytes: 50_000)

        #expect(await duplicates(in: sandbox.url).isEmpty)
    }

    @Test("Collects files at or above the large-file threshold, largest first")
    func largeFiles() throws {
        let sandbox = try Sandbox()
        try sandbox.file("small.bin", bytes: 10_000)
        try sandbox.file("big.bin", bytes: 400_000)
        try sandbox.file("bigger.bin", bytes: 800_000)

        let inventory = FileScanner.inventory(
            roots: [sandbox.url], largeThreshold: 300_000, duplicateThreshold: .max, progress: { _ in })

        #expect(inventory.large.map(\.url.lastPathComponent) == ["bigger.bin", "big.bin"])
        #expect(inventory.scannedFiles == 3)
    }

    @Test(
        "Classifies files by extension",
        arguments: [
            ("movie.MOV", FileKind.video), ("Xcode.xip", .diskImage), ("setup.dmg", .diskImage),
            ("backup.tar.gz", .archive), ("photos.zip", .archive), ("notes.txt", .other),
        ])
    func kinds(name: String, kind: FileKind) {
        #expect(FileKind.of(URL(fileURLWithPath: "/tmp/\(name)")) == kind)
    }
}

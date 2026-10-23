import Foundation

nonisolated struct ProcessResult: Sendable {
    let status: Int32
    let stdout: Data
    let stderr: String

    var succeeded: Bool { status == 0 }
}

nonisolated enum ProcessError: LocalizedError {
    case failed(command: String, status: Int32, stderr: String)

    var errorDescription: String? {
        switch self {
        case let .failed(command, status, stderr):
            let detail = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return "\(command) exited with \(status)" + (detail.isEmpty ? "" : ": \(detail)")
        }
    }
}

/// Runs external tools with an explicit argument array — never through a shell string.
nonisolated enum ProcessRunner {
    static func run(_ executable: String, _ arguments: [String]) async throws -> ProcessResult {
        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            let out = Pipe()
            let err = Pipe()
            process.standardOutput = out
            process.standardError = err
            process.standardInput = FileHandle.nullDevice
            try process.run()

            // Drain both pipes concurrently so a full buffer can't deadlock the child.
            async let errData = Task.detached { err.fileHandleForReading.readDataToEndOfFile() }.value
            let outData = out.fileHandleForReading.readDataToEndOfFile()
            let stderrData = await errData
            process.waitUntilExit()

            return ProcessResult(
                status: process.terminationStatus,
                stdout: outData,
                stderr: String(decoding: stderrData, as: UTF8.self)
            )
        }.value
    }

    /// Runs and throws on a non-zero exit status.
    @discardableResult
    static func checked(_ executable: String, _ arguments: [String]) async throws -> ProcessResult {
        let result = try await run(executable, arguments)
        guard result.succeeded else {
            let name = ([URL(fileURLWithPath: executable).lastPathComponent] + arguments.prefix(2)).joined(
                separator: " ")
            throw ProcessError.failed(command: name, status: result.status, stderr: result.stderr)
        }
        return result
    }
}

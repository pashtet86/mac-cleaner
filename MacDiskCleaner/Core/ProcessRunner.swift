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
    /// - Parameters:
    ///   - environment: replaces the child's environment when given (e.g. the login shell's PATH).
    ///   - timeout: terminates the child after this many seconds — for tools that can hang.
    static func run(
        _ executable: String, _ arguments: [String], environment: [String: String]? = nil,
        timeout: TimeInterval? = nil
    ) async throws -> ProcessResult {
        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            if let environment { process.environment = environment }
            process.standardInput = FileHandle.nullDevice

            if let timeout {
                // Output goes to temporary files, not pipes: a background helper the tool spawns
                // (shell prompts, daemons) can keep a pipe open forever, but we only wait for the
                // process itself and read the files once it has exited or been stopped.
                let folder = FileManager.default.temporaryDirectory.appending(path: "proc-\(UUID().uuidString)")
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                defer { try? FileManager.default.removeItem(at: folder) }
                let outURL = folder.appending(path: "out")
                let errURL = folder.appending(path: "err")
                FileManager.default.createFile(atPath: outURL.path, contents: nil)
                FileManager.default.createFile(atPath: errURL.path, contents: nil)
                let outHandle = try FileHandle(forWritingTo: outURL)
                let errHandle = try FileHandle(forWritingTo: errURL)
                process.standardOutput = outHandle
                process.standardError = errHandle
                try process.run()
                let child = RunningProcess(process)
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { child.terminateIfRunning() }
                process.waitUntilExit()
                try? outHandle.close()
                try? errHandle.close()
                return ProcessResult(
                    status: process.terminationStatus,
                    stdout: (try? Data(contentsOf: outURL)) ?? Data(),
                    stderr: String(decoding: (try? Data(contentsOf: errURL)) ?? Data(), as: UTF8.self)
                )
            }

            let out = Pipe()
            let err = Pipe()
            process.standardOutput = out
            process.standardError = err
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

/// Lets the timeout closure hold the process; `terminate()` is safe to call from any thread.
nonisolated private final class RunningProcess: @unchecked Sendable {
    private let process: Process
    init(_ process: Process) { self.process = process }
    func terminateIfRunning() { if process.isRunning { process.terminate() } }
}

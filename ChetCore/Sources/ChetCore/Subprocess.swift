import Foundation
import Synchronization

/// Runs short-lived command-line tools (diskutil, tmutil, brew) with a wall-clock timeout.
public enum Subprocess {
    public struct Result: Sendable {
        public let status: Int32
        public let out: String
        public let err: String
        public var ok: Bool { status == 0 }
        /// Error lines when the command failed, else stdout, for surfacing a failure to the user.
        public var message: String {
            let trimmed = err.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? out.trimmingCharacters(in: .whitespacesAndNewlines) : trimmed
        }
    }

    /// Runs `tool` with `args`, draining both pipes concurrently so a full stderr buffer cannot
    /// stall the child. Terminates the child past `timeout`, which reports as a non-zero status.
    public static func run(
        _ tool: String, _ args: [String], env: [String: String]? = nil, timeout: TimeInterval = 20
    ) -> Result {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = args
        if let env { process.environment = env }
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return Result(status: -1, out: "", err: error.localizedDescription)
        }

        let errBox = Mutex(Data())
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            errBox.withLock { $0 = errPipe.fileHandleForReading.readDataToEndOfFile() }
            group.leave()
        }
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()

        // ponytail: wall-clock watchdog, one-shot CLI calls only, no per-call thread pool.
        let watchdog = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)
        process.waitUntilExit()
        watchdog.cancel()
        group.wait()
        let errData = errBox.withLock { $0 }
        return Result(
            status: process.terminationStatus,
            out: String(decoding: outData, as: UTF8.self),
            err: String(decoding: errData, as: UTF8.self))
    }
}

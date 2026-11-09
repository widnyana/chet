import Foundation

public struct LocalSnapshot: Sendable, Hashable {
    /// For example `com.apple.TimeMachine.2026-11-03-101500.local`.
    public let name: String
    /// For example `2026-11-03-101500`, the argument `tmutil deletelocalsnapshots` takes.
    public let date: String
}

extension LocalSnapshot: Identifiable {
    public var id: String { name }
}

public enum SnapshotError: Error, Equatable {
    case failed(Int32)
}

/// Time Machine local snapshots of the boot volume, through `/usr/bin/tmutil`.
public enum Snapshots {
    public static func parse(_ output: String) -> [LocalSnapshot] {
        let prefix = "com.apple.TimeMachine."
        let suffix = ".local"
        return output.split(whereSeparator: \.isNewline).compactMap { line in
            let name = line.trimmingCharacters(in: .whitespaces)
            guard name.hasPrefix(prefix), name.hasSuffix(suffix) else { return nil }
            return LocalSnapshot(name: name, date: String(name.dropFirst(prefix.count).dropLast(suffix.count)))
        }
    }

    public static func list() throws -> [LocalSnapshot] {
        parse(try tmutil(["listlocalsnapshots", "/"]))
    }

    /// Deletes a local snapshot with `tmutil`. A dry run runs no `tmutil` call at all.
    public static func delete(_ snapshot: LocalSnapshot, dryRun: Bool) throws {
        guard !dryRun else { return }
        _ = try tmutil(["deletelocalsnapshots", snapshot.date])
    }

    static func tmutil(_ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tmutil")
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw SnapshotError.failed(process.terminationStatus) }
        return String(decoding: data, as: UTF8.self)
    }
}

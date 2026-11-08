import Foundation

/// DRY_RUN gate: when set to `true` or `1` (case-insensitive), cleaning reports success but
/// no file is ever removed. Read from the process environment first, then from a `.env` file
/// found walking up from the working directory or the running bundle — so `source .env` in
/// the repo, `swift test`, the CLI, and the launched app all behave the same.
public enum DryRun {
    /// Resolved once per process: the environment does not change mid-run.
    public static let enabled: Bool = {
        if let raw = ProcessInfo.processInfo.environment["DRY_RUN"] { return parse(raw) }
        var roots = [URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)]
        roots.append(Bundle.main.bundleURL)
        return roots.contains { envFileValue(from: $0) }
    }()

    /// Untrusted string → trusted bool. Only `true` and `1` enable the gate.
    static func parse(_ raw: String?) -> Bool {
        guard let raw else { return false }
        return ["true", "1"].contains(raw.trimmingCharacters(in: .whitespaces).lowercased())
    }

    /// First `.env` found walking up from `start` wins; later files are ignored.
    static func envFileValue(from start: URL) -> Bool {
        var dir = start.standardizedFileURL
        while true {
            if let text = try? String(contentsOf: dir.appendingPathComponent(".env"), encoding: .utf8) {
                return parse(
                    text.split(separator: "\n").first { $0.trimmingCharacters(in: .whitespaces).hasPrefix("DRY_RUN=") }?
                        .dropFirst("DRY_RUN=".count).trimmingCharacters(in: .whitespaces))
            }
            if dir.path == "/" { return false }
            dir.deleteLastPathComponent()
        }
    }
}

import Darwin
import Foundation

/// Launch-time log housekeeping: rotate a stale crash report aside and prune the history.
/// Pure file operations on the shared log directory so the AppDelegate stays thin and the
/// behavior is unit-testable.
public enum LogMaintenance {
    /// If `crash.txt` exists, atomically renames it to `crash-<unix-time>.txt` and returns
    /// true (the caller logs "previous crash detected"). Fresh-file creation is the crash
    /// handler's job: rotation must precede install, or the pre-opened append fd would keep
    /// pointing at the renamed historical inode.
    @discardableResult
    public static func rotateStaleCrashReport(
        in directory: URL, now: @escaping () -> TimeInterval = { Date().timeIntervalSince1970 }
    ) -> Bool {
        let crash = directory.appendingPathComponent("crash.txt")
        // Millisecond precision: two rotations within one second must not collide.
        let stamp = String(format: "%.0f", now() * 1_000)
        let rotated = directory.appendingPathComponent("crash-\(stamp).txt")
        // Rename directly: ENOENT and any other failure both map to "no stale report rotated".
        return rename(crash.path, rotated.path) == 0
    }

    /// Keeps the newest `kept` rotated names matching `prefix` and `suffix` by modification
    /// date, deletes the rest, and returns how many rotated names survive. The live
    /// `application-debug.log` is never deleted or counted.
    public static func pruneLogs(in directory: URL, prefix: String, suffix: String, kept: Int) -> Int {
        let liveName = "application-debug.log"
        let contents =
            (try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        var rotated: [(url: URL, modified: Date)] = []
        for url in contents {
            let name = url.lastPathComponent
            guard name != liveName, name.hasPrefix(prefix), name.hasSuffix(suffix) else { continue }
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
            if let modified = values?.contentModificationDate {
                rotated.append((url: url, modified: modified))
            } else {
                rotated.append((url: url, modified: Date.distantPast))
            }
        }
        rotated.sort { lhs, rhs in
            if lhs.modified != rhs.modified { return lhs.modified > rhs.modified }
            return lhs.url.lastPathComponent > rhs.url.lastPathComponent
        }
        let survivors = min(max(kept, 0), rotated.count)
        for candidate in rotated.dropFirst(survivors) {
            try? FileManager.default.removeItem(at: candidate.url)
        }
        return survivors
    }

    /// Keeps the newest `kept` `crash-<timestamp>.txt` files by modification date, deletes
    /// older ones.
    public static func pruneCrashHistory(in directory: URL, kept: Int = 5) {
        _ = pruneLogs(in: directory, prefix: "crash-", suffix: ".txt", kept: kept)
    }

    /// The full launch sequence: rotate a stale crash report aside, prune history, and report
    /// whether a previous crash was seen (for the flight event and OSLog line).
    public static func launchCheck(
        in directory: URL, now: @escaping () -> TimeInterval = { Date().timeIntervalSince1970 }
    ) -> Bool {
        let sawCrash = rotateStaleCrashReport(in: directory, now: now)
        pruneCrashHistory(in: directory)
        return sawCrash
    }
}

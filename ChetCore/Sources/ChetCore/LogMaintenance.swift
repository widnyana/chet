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

    /// Keeps the newest `kept` `crash-<timestamp>.txt` files, deletes older ones.
    public static func pruneCrashHistory(in directory: URL, kept: Int = 5) {
        let contents = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        let history =
            contents
            .filter { $0.hasPrefix("crash-") && $0.hasSuffix(".txt") }
            .sorted()
        guard history.count > kept else { return }
        for name in history.prefix(history.count - kept) {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
        }
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

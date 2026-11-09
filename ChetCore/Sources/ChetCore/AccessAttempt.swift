import Darwin
import Foundation

/// Durable record that the user has already been sent to grant Full Disk Access.
///
/// This exists because `UserDefaults` does not survive this particular sequence: macOS
/// SIGKILLs the app the moment a Full Disk Access grant is toggled, before the preference
/// daemon flushes. A tiny marker file written with `fsync` before leaving the app does
/// survive, so the relaunch never blocks again.
public enum AccessAttempt {
    public static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/chet/grant-attempted")
    }

    /// True when a previous run already sent the user to Settings.
    public static func hasAttempted(url: URL = defaultURL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    /// Writes the marker and forces it to disk. Returns false when it could not be written.
    @discardableResult
    public static func record(url: URL = defaultURL) -> Bool {
        let directory = url.deletingLastPathComponent()
        guard (try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)) != nil
        else { return false }
        let fd = open(url.path, O_WRONLY | O_CREAT, 0o644)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        let payload = Array("attempted\n".utf8)
        let written = payload.withUnsafeBytes { write(fd, $0.baseAddress!, payload.count) }
        guard written == payload.count else { return false }
        // Without this the kernel may not have handed the bytes to the disk when macOS
        // kills us; the marker would vanish exactly when it matters.
        guard fsync(fd) == 0 else { return false }
        return true
    }

    /// Clears the marker (used by tests and by "start over" flows).
    public static func clear(url: URL = defaultURL) {
        try? FileManager.default.removeItem(at: url)
    }
}

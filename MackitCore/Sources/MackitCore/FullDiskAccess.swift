import Foundation

/// macOS gives no API to ask for Full Disk Access status, so read a TCC-protected file.
public enum FullDiskAccess {
    public enum Status: Sendable {
        case granted, denied
    }

    public static let settingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!

    public static var defaultProbes: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            home.appendingPathComponent("Library/Application Support/com.apple.TCC/TCC.db"),
            home.appendingPathComponent("Library/Safari/Bookmarks.plist"),
        ]
    }

    /// Granted when ANY existing probe file can be opened for reading. Trying all of them
    /// matters: one probe may be restricted for reasons unrelated to this grant (a
    /// root-only TCC.db), and failing on it alone would report denied forever despite
    /// access having been granted.
    public static func status(probing probes: [URL] = defaultProbes) -> Status {
        let existing = probes.filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !existing.isEmpty else { return .denied }
        for probe in existing {
            if let handle = try? FileHandle(forReadingFrom: probe) {
                try? handle.close()
                return .granted
            }
        }
        return .denied
    }
}

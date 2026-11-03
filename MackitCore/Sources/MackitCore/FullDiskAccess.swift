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

    /// Granted when the first existing probe file can be opened for reading.
    public static func status(probing probes: [URL] = defaultProbes) -> Status {
        guard let probe = probes.first(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
            return .denied
        }
        guard let handle = try? FileHandle(forReadingFrom: probe) else { return .denied }
        try? handle.close()
        return .granted
    }
}

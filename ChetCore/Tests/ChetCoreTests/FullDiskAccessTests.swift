import Darwin
import Foundation
import Testing

@testable import ChetCore

struct FullDiskAccessTests {
    @Test func readableProbeIsGranted() throws {
        let dir = try TempDir()
        let probe = try dir.file("TCC.db", bytes: 10)
        #expect(FullDiskAccess.status(probing: [probe]) == .granted)
    }

    @Test func unreadableProbeIsDenied() throws {
        let dir = try TempDir()
        let probe = try dir.file("TCC.db", bytes: 10)
        #expect(chmod(probe.path, 0o000) == 0)
        defer { chmod(probe.path, 0o644) }
        #expect(FullDiskAccess.status(probing: [probe]) == .denied)
    }

    @Test func oneRestrictedProbeAmongReadableOnesIsGranted() throws {
        let dir = try TempDir()
        let restricted = try dir.file("TCC.db", bytes: 10)
        let readable = try dir.file("Bookmarks.plist", bytes: 10)
        #expect(chmod(restricted.path, 0o000) == 0)
        defer { chmod(restricted.path, 0o644) }
        // The restricted probe comes first; a later readable one must still grant access.
        #expect(FullDiskAccess.status(probing: [restricted, readable]) == .granted)
    }

    @Test func noProbeFileIsDenied() {
        #expect(FullDiskAccess.status(probing: [URL(fileURLWithPath: "/nonexistent/chet/TCC.db")]) == .denied)
    }
}

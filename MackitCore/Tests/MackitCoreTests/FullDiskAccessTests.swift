import Darwin
import Foundation
import Testing

@testable import MackitCore

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

    @Test func noProbeFileIsDenied() {
        #expect(FullDiskAccess.status(probing: [URL(fileURLWithPath: "/nonexistent/mackit/TCC.db")]) == .denied)
    }
}

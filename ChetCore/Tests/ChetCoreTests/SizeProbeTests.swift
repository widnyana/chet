import Darwin
import Foundation
import Testing

@testable import ChetCore

struct SizeProbeTests {
    @Test func normalFileReportsFullSize() throws {
        let dir = try TempDir()
        let file = try dir.file("plain", bytes: 10_000_000)
        let bytes = try #require(SizeProbe.reclaimableBytes(file))
        #expect(bytes > 9_000_000)
    }

    @Test func apfsCloneReportsNearZero() throws {
        let dir = try TempDir()
        let source = try dir.file("source", bytes: 10_000_000)
        let clone = dir.url.appendingPathComponent("clone")
        #expect(clonefile(source.path, clone.path, 0) == 0)
        let bytes = try #require(SizeProbe.reclaimableBytes(clone))
        #expect(bytes < 100_000)
    }

    @Test func missingFileReturnsNil() {
        #expect(SizeProbe.reclaimableBytes(URL(fileURLWithPath: "/nonexistent/chet")) == nil)
    }
}

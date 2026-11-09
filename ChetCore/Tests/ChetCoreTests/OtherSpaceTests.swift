import Foundation
import Testing

@testable import ChetCore

struct OtherSpaceTests {
    @Test func routesSkippedFoldersByReason() throws {
        let dir = try TempDir()
        try dir.file("big/data.bin", bytes: 1_000_000)
        try dir.file("small/data.bin", bytes: 10_000)
        let big = dir.url.appendingPathComponent("big").path
        let small = dir.url.appendingPathComponent("small").path
        let info = OtherSpace.measure(skipped: [
            (big, .user),
            (small, .always),
            ("/Users/someone/iCloud", .cloud),
            ("/Volumes/share", .network),
        ])
        #expect(info.folders.map(\.path) == [big, small])
        #expect(info.folders.allSatisfy { $0.size > 0 })
        #expect(info.cloudFolders == ["/Users/someone/iCloud"])
    }

    @Test func measureWithNoSkipsDoesNotThrow() {
        let info = OtherSpace.measure(skipped: [])
        #expect(info.folders.isEmpty)
        #expect(info.cloudFolders.isEmpty)
    }
}

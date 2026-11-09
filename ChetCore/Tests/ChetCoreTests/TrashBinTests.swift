import Foundation
import Testing

@testable import ChetCore

struct TrashBinTests {
    @Test func emptyRemovesTopLevelItemsAndReportsFreed() throws {
        let dir = try TempDir()
        try dir.file("trash/a.bin", bytes: 4096)
        try dir.file("trash/sub/b.bin", bytes: 4096)
        let trash = dir.url.appendingPathComponent("trash")
        #expect(TrashBin.size(at: trash) >= 8192)
        let result = TrashBin.empty(at: trash)
        #expect(result.removed == 2)
        #expect(result.failed.isEmpty)
        #expect(result.freed >= 8192)
        #expect((FS.list(trash.path) ?? []).isEmpty)
    }
}

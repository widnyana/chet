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
        let result = TrashBin.empty(at: trash, dryRun: false)
        #expect(result.removed == 2)
        #expect(result.failed.isEmpty)
        #expect(result.freed >= 8192)
        #expect((FS.list(trash.path) ?? []).isEmpty)
    }

    @Test func dryRunEmptyReportsRemovedAndFreedButKeepsFiles() throws {
        let dir = try TempDir()
        try dir.file("trash/a.bin", bytes: 4096)
        try dir.file("trash/sub/b.bin", bytes: 4096)
        let trash = dir.url.appendingPathComponent("trash")
        let result = TrashBin.empty(at: trash, dryRun: true)
        #expect(result.removed == 2)
        #expect(result.failed.isEmpty)
        #expect(result.freed >= 8192)
        #expect((FS.list(trash.path) ?? []).contains("a.bin"))
    }

    @Test func emptyOnEmptyDirectoryReportsZeros() throws {
        let dir = try TempDir()
        let result = TrashBin.empty(at: dir.url, dryRun: false)
        #expect(result.removed == 0)
        #expect(result.failed.isEmpty)
        #expect(result.freed == 0)
        #expect((FS.list(dir.url.path) ?? []).isEmpty)
    }

    @Test func secondEmptyReportsNothingAndNoFailures() throws {
        let dir = try TempDir()
        try dir.file("trash/a.bin", bytes: 4096)
        let trash = dir.url.appendingPathComponent("trash")
        let first = TrashBin.empty(at: trash, dryRun: false)
        #expect(first.removed == 1)
        let second = TrashBin.empty(at: trash, dryRun: false)
        #expect(second.removed == 0)
        #expect(second.failed.isEmpty)
        #expect(second.freed == 0)
        #expect((FS.list(trash.path) ?? []).isEmpty)
    }
}

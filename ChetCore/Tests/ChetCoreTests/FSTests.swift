import Foundation
import Testing

@testable import ChetCore

struct FSTests {
    @Test func usageSumsFilesAndSkipsSymlinks() throws {
        let dir = try TempDir()
        try dir.file("a/one.bin", bytes: 4096)
        try dir.file("a/b/two.bin", bytes: 8192)
        try FileManager.default.createSymbolicLink(
            at: dir.url.appendingPathComponent("a/link"),
            withDestinationURL: dir.url.appendingPathComponent("a"))
        let usage = FS.usage(dir.url.appendingPathComponent("a").path)
        #expect(usage.files == 2)
        #expect(usage.size >= 12_288)
    }

    @Test func listReturnsChildrenAndNilForMissing() throws {
        let dir = try TempDir()
        try dir.file("x/one", bytes: 1)
        try dir.file("x/two", bytes: 1)
        #expect(Set(FS.list(dir.url.appendingPathComponent("x").path) ?? []) == ["one", "two"])
        #expect(FS.list(dir.url.appendingPathComponent("nope").path) == nil)
    }
}

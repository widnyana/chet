import Foundation
import Testing

@testable import ChetCore

struct FileWalkerTests {
    @Test func doesNotFollowSymlinkOutOfTree() throws {
        let dir = try TempDir()
        try dir.file("a/file", bytes: 10)
        try FileManager.default.createSymbolicLink(
            at: dir.url.appendingPathComponent("root"), withDestinationURL: URL(fileURLWithPath: "/"))
        var seen: [URL] = []
        try FileWalker(policy: dir.policy).walk(dir.url) { seen.append($0.url) }
        #expect(seen.count == 1)
        #expect(seen.allSatisfy { $0.path.hasPrefix(dir.url.path) })
    }

    @Test func skipsPolicyDeniedFiles() throws {
        let dir = try TempDir()
        try dir.file("code/.git/config", bytes: 10)
        try dir.file("code/main.swift", bytes: 10)
        var names: [String] = []
        try FileWalker(policy: dir.policy).walk(dir.url) { names.append($0.url.lastPathComponent) }
        #expect(names == ["main.swift"])
    }

    @Test func skipsPackageContentsAndSymlinks() throws {
        let dir = try TempDir()
        try dir.file("plain.txt", bytes: 10)
        try dir.file("nested/deep/file.txt", bytes: 10)
        try dir.file("Thing.app/Contents/MacOS/thing", bytes: 10)
        try FileManager.default.createSymbolicLink(
            at: dir.url.appendingPathComponent("link"),
            withDestinationURL: dir.url.appendingPathComponent("plain.txt"))
        var names: [String] = []
        try FileWalker(policy: dir.policy).walk(dir.url) { names.append($0.url.lastPathComponent) }
        #expect(names.sorted() == ["file.txt", "plain.txt"])
    }

    @Test func fileRootIsItsOwnEntry() throws {
        let dir = try TempDir()
        let file = try dir.file("one.txt", bytes: 10)
        var names: [String] = []
        try FileWalker(policy: dir.policy).walk(file) { names.append($0.url.lastPathComponent) }
        #expect(names == ["one.txt"])
    }

    @Test func stampsMatchTheDirectoryRecord() throws {
        let dir = try TempDir()
        let file = try dir.file("sized.bin", bytes: 4096)
        var found: [WalkEntry] = []
        try FileWalker(policy: dir.policy).walk(dir.url) { found.append($0) }
        let entry = try #require(found.first { $0.url.lastPathComponent == "sized.bin" })
        #expect(entry.stamp == FileStamp.read(file))
        #expect(entry.reclaimableBytes > 0)
    }

    @Test func stopsOnCancellation() async throws {
        let dir = try TempDir()
        for i in 0..<20 { try dir.file("f\(i)", bytes: 10) }
        let walker = FileWalker(policy: dir.policy)
        let task = Task { () throws -> Int in
            var count = 0
            try walker.walk(dir.url) { _ in
                count += 1
                withUnsafeCurrentTask { $0?.cancel() }
            }
            return count
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test func datalessFlagIsRead() {
        #expect(FileStamp.isDataless(flags: 0x4000_0000))
        #expect(FileStamp.isDataless(flags: 0x4000_0000 | 0x20))
        #expect(!FileStamp.isDataless(flags: 0))
        #expect(!FileStamp.isDataless(flags: 0x20))
    }

    @Test func localFilesAreNotDataless() throws {
        let dir = try TempDir()
        let file = try dir.file("a", bytes: 10)
        #expect(FileStamp.read(file)?.isDataless == false)
    }

    @Test func hardLinksCountOnce() throws {
        let dir = try TempDir()
        let a = try dir.file("a", bytes: 1_000_000)
        #expect(link(a.path, dir.url.appendingPathComponent("b").path) == 0)
        let total = try FileWalker(policy: dir.policy).totalSize(dir.url)
        #expect(total >= 900_000 && total < 1_500_000)
    }
}

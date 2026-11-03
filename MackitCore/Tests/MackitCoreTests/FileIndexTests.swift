import Darwin
import Foundation
import Testing

@testable import MackitCore

struct FileIndexTests {
    private func lstatOf(_ url: URL) throws -> stat {
        var st = stat()
        #expect(lstat(url.path, &st) == 0)
        return st
    }

    private func entries(in url: URL) throws -> [String: FileIndexBuilder.Entry] {
        let fd = open(url.path, O_RDONLY | O_DIRECTORY)
        #expect(fd >= 0)
        defer { close(fd) }
        var found: [String: FileIndexBuilder.Entry] = [:]
        try FileIndexBuilder.forEachEntry(fd) { found[$0.name] = $0 }
        return found
    }

    /// Sum of allocated bytes of every regular file below `url`, counting hard links once.
    private func expectedAllocated(_ url: URL) throws -> Int64 {
        var seen = Set<UInt64>()
        var total: Int64 = 0
        let walker = FileManager.default.enumerator(atPath: url.path)
        while let relative = walker?.nextObject() as? String {
            let st = try lstatOf(url.appendingPathComponent(relative))
            guard (st.st_mode & S_IFMT) == S_IFREG else { continue }
            if st.st_nlink > 1, !seen.insert(UInt64(st.st_ino)).inserted { continue }
            total += Int64(st.st_blocks) * 512
        }
        return total
    }

    private func writeTag(_ dir: TempDir, _ folder: String, _ text: String) throws {
        let url = dir.url.appendingPathComponent(folder).appendingPathComponent("CACHEDIR.TAG")
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    @Test func bulkEntriesMatchLstat() throws {
        let dir = try TempDir()
        let small = try dir.file("small", bytes: 10)
        let big = try dir.file("big", bytes: 2_000_000)
        try dir.file("sub/inner", bytes: 5)
        #expect(link(big.path, dir.url.appendingPathComponent("link").path) == 0)
        let found = try entries(in: dir.url)
        #expect(Set(found.keys) == ["small", "big", "sub", "link"])
        for url in [small, big] {
            let st = try lstatOf(url)
            let entry = try #require(found[url.lastPathComponent])
            #expect(entry.kind == .file)
            #expect(entry.inode == UInt64(st.st_ino))
            #expect(entry.size == Int64(st.st_size))
            #expect(entry.allocatedSize == Int64(st.st_blocks) * 512)
            #expect(entry.links == UInt16(st.st_nlink))
            #expect(entry.modified == FileStamp.read(url)?.modified)
            #expect(entry.device == st.st_dev)
        }
        #expect(found["sub"]?.kind == .directory)
        #expect(found["link"]?.links == 2)
    }

    @Test func candidatesSkipPackagesGitAndTaggedCaches() throws {
        let dir = try TempDir()
        try dir.file("big", bytes: 2_000_000)
        try dir.file("small", bytes: 10)
        try dir.file("photo.jpg", bytes: 10)
        try dir.file("code/.git/objects/pack", bytes: 2_000_000)
        try dir.file("Tool.app/Contents/blob", bytes: 2_000_000)
        try dir.file("tagged/blob", bytes: 2_000_000)
        try writeTag(dir, "tagged", "Signature: 8a477f597d28d172789f06886806bc55\n# made by a test\n")
        try dir.file("wrongtag/blob", bytes: 2_000_000)
        try writeTag(dir, "wrongtag", "Signature: not-the-real-one\n")
        let index = try FileIndexBuilder(policy: dir.policy).build(roots: [dir.url])
        let relative = Set(index.candidates.map { String($0.url.path.dropFirst(dir.url.path.count + 1)) })
        #expect(relative == ["big", "photo.jpg", "wrongtag/blob"])
        #expect(index.taggedCaches.map(\.url.lastPathComponent) == ["tagged"])
        #expect((index.taggedCaches.first?.bytes ?? 0) >= 2_000_000)
    }

    @Test func treeTotalsMatchIndependentSum() throws {
        let dir = try TempDir()
        try dir.file("a/x", bytes: 1_500_000)
        try dir.file("a/b/y", bytes: 2_500_000)
        try dir.file("z", bytes: 1_200_000)
        try dir.file("tiny", bytes: 3)
        let a = try dir.file("hard", bytes: 1_000_000)
        #expect(link(a.path, dir.url.appendingPathComponent("a/hard2").path) == 0)
        let tree = try #require(try FileIndexBuilder(policy: dir.policy).build(roots: [dir.url]).trees.first)
        #expect(tree.size == (try expectedAllocated(dir.url)))
        #expect(tree.children.first?.url.lastPathComponent == "a")
        #expect(tree.children.map(\.size) == tree.children.map(\.size).sorted(by: >))
        #expect(!tree.children.contains { $0.url.lastPathComponent == "tiny" })
        #expect(FileIndexBuilder.allocatedSize(of: dir.url) == tree.size)
        #expect(
            FileIndexBuilder.allocatedSize(of: dir.url.appendingPathComponent("z")) == Int64(
                try lstatOf(dir.url.appendingPathComponent("z")).st_blocks) * 512)
    }

    @Test func maxDepthLimitsTreeButNotTotals() throws {
        let dir = try TempDir()
        try dir.file("a/b/c/d", bytes: 1_500_000)
        var builder = FileIndexBuilder(policy: dir.policy)
        builder.maxDepth = 1
        let tree = try #require(try builder.build(roots: [dir.url]).trees.first)
        let a = try #require(tree.children.first)
        #expect(a.children.isEmpty)
        #expect(a.size == tree.size)
        #expect(tree.size >= 1_500_000)
    }

    @Test func symlinksAreNotFollowed() throws {
        let dir = try TempDir()
        try dir.file("real", bytes: 10)
        try FileManager.default.createSymbolicLink(
            at: dir.url.appendingPathComponent("root"), withDestinationURL: URL(fileURLWithPath: "/"))
        let index = try FileIndexBuilder(policy: dir.policy).build(roots: [dir.url])
        #expect(index.entriesSeen == 2)
        #expect(index.trees.first?.size == (try expectedAllocated(dir.url)))
    }

    @Test func progressCountsEntriesAndBytes() throws {
        let dir = try TempDir()
        try dir.file("a/x", bytes: 1_500_000)
        try dir.file("y", bytes: 10)
        let progress = ScanProgress()
        let index = try FileIndexBuilder(policy: dir.policy, progress: progress).build(roots: [dir.url])
        #expect(progress.files == index.entriesSeen)
        #expect(progress.bytes == index.trees.first?.size)
        #expect(!progress.currentFolder.isEmpty)
    }

    @Test func cancellationStopsTheWalk() async throws {
        let dir = try TempDir()
        for i in 0..<20 { try dir.file("f\(i)", bytes: 10) }
        let builder = FileIndexBuilder(policy: dir.policy)
        let task = Task { () throws -> FileIndex in
            withUnsafeCurrentTask { $0?.cancel() }
            return try builder.build(roots: [dir.url])
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }
}

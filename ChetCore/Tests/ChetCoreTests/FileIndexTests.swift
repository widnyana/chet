import Darwin
import Foundation
import Testing

@testable import ChetCore

struct FileIndexTests {
    private func lstatOf(_ url: URL) throws -> stat {
        var st = stat()
        #expect(lstat(url.path, &st) == 0)
        return st
    }

    private func entries(in url: URL) async throws -> [String: FileIndexBuilder.Entry] {
        let fd = open(url.path, O_RDONLY | O_DIRECTORY)
        #expect(fd >= 0)
        defer { close(fd) }
        var found: [String: FileIndexBuilder.Entry] = [:]
        try await FileIndexBuilder.forEachEntry(fd) { found[$0.name] = $0 }
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

    @Test func bulkEntriesMatchLstat() async throws {
        let dir = try TempDir()
        let small = try dir.file("small", bytes: 10)
        let big = try dir.file("big", bytes: 2_000_000)
        try dir.file("sub/inner", bytes: 5)
        #expect(link(big.path, dir.url.appendingPathComponent("link").path) == 0)
        let found = try await entries(in: dir.url)
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
            // APFS reports private size in the bulk record; an un-cloned file owns all its blocks.
            #expect(entry.hasPrivateSize)
            #expect(entry.privateSize == entry.allocatedSize)
        }
        #expect(found["sub"]?.kind == .directory)
        #expect(found["link"]?.links == 2)
    }

    /// Clone semantics in the bulk record (verified empirically on APFS): a persisting `clonefile`
    /// pair reports private size 0 for both members, a partially modified clone holds only its
    /// unshared blocks, and the survivor of a deleted twin owns its full allocation again.
    @Test func bulkPrivateSizeMatchesCloneSemantics() async throws {
        let dir = try TempDir()
        let orig = try dir.file("orig", bytes: 1_000_000)
        let clone = dir.url.appendingPathComponent("clone")
        let cloned = clone.withUnsafeFileSystemRepresentation { dst in
            orig.withUnsafeFileSystemRepresentation { src in
                // clonefile(); ENOTSUP on volumes without clone support.
                clonefile(src, dst, 0) == 0
            }
        }
        let pair = try await entries(in: dir.url)
        let origEntry = try #require(pair["orig"])
        #expect(origEntry.hasPrivateSize)
        if cloned {
            let cloneEntry = try #require(pair["clone"])
            #expect(cloneEntry.hasPrivateSize)
            #expect(origEntry.privateSize == 0)
            #expect(cloneEntry.privateSize == 0)
            // Partially modify the clone: only the rewritten blocks become private.
            let fh = try FileHandle(forWritingTo: clone)
            try fh.seek(toOffset: 4096)
            try fh.write(Data(repeating: 0xFF, count: 4096))
            try fh.close()
            let partial = try #require(try await entries(in: dir.url)["clone"])
            #expect(partial.privateSize > 0)
            #expect(partial.privateSize < partial.allocatedSize)
            // Deleting the twin gives the survivor its full allocation back.
            try FileManager.default.removeItem(at: orig)
            let survivor = try #require(try await entries(in: dir.url)["clone"])
            #expect(survivor.privateSize == survivor.allocatedSize)
        } else {
            #expect(origEntry.privateSize == origEntry.allocatedSize)
        }
    }

    /// AE2: a hardlinked file is counted once and yields exactly one candidate, at the smallest
    /// gate-passing path regardless of discovery order.
    @Test func hardlinkCountsOnceAndEmitsOneCandidate() async throws {
        let dir = try TempDir()
        let first = try dir.file("Documents/a.bin", bytes: 1_500_000)
        try FileManager.default.createDirectory(
            at: dir.url.appendingPathComponent("Downloads"), withIntermediateDirectories: true)
        #expect(link(first.path, dir.url.appendingPathComponent("Downloads/b.bin").path) == 0)
        let index = try await FileIndexBuilder(policy: dir.policy).build(roots: [
            dir.url.appendingPathComponent("Downloads"), dir.url.appendingPathComponent("Documents"),
        ])
        #expect(index.trees.reduce(0) { $0 + $1.size } == Int64(try lstatOf(first).st_blocks) * 512)
        let candidates = index.candidates.filter {
            $0.stamp.isRegularFile && $0.url.lastPathComponent.hasSuffix(".bin")
        }
        #expect(candidates.count == 1)
        #expect(candidates.first?.url.path == dir.url.appendingPathComponent("Documents/a.bin").path)
    }

    /// A hardlink first discovered in a no-candidates folder (.git) still yields its eligible
    /// sibling path.
    @Test func hardlinkInExcludedFolderStillYieldsEligibleSibling() async throws {
        let dir = try TempDir()
        let hidden = try dir.file(".git/objects/blob", bytes: 1_500_000)
        try FileManager.default.createDirectory(
            at: dir.url.appendingPathComponent("Documents"), withIntermediateDirectories: true)
        #expect(link(hidden.path, dir.url.appendingPathComponent("Documents/blob").path) == 0)
        let index = try await FileIndexBuilder(policy: dir.policy).build(roots: [dir.url])
        let candidates = index.candidates.filter { $0.url.lastPathComponent == "blob" }
        #expect(candidates.count == 1)
        #expect(candidates.first?.url.deletingLastPathComponent().lastPathComponent == "Documents")
    }

    /// A mode-000 subdirectory is recorded as a read error; totals reflect readable content only.
    @Test func unreadableFoldersAreRecordedAndTotalsBestKnown() async throws {
        let dir = try TempDir()
        let ok = try dir.file("ok/x", bytes: 1_500_000)
        let locked = dir.url.appendingPathComponent("locked")
        try dir.file("locked/inner", bytes: 10)
        #expect(chmod(locked.path, 0o000) == 0)
        defer { chmod(locked.path, 0o755) }
        let index = try await FileIndexBuilder(policy: dir.policy).build(roots: [dir.url])
        #expect(index.readErrors.count == 1)
        #expect(index.readErrors.first?.url.lastPathComponent == "locked")
        #expect(index.readErrors.first?.errno == EACCES)
        #expect(index.trees.first?.size == Int64(try lstatOf(ok).st_blocks) * 512)
    }

    @Test func candidatesSkipPackagesGitAndTaggedCaches() async throws {
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
        let index = try await FileIndexBuilder(policy: dir.policy).build(roots: [dir.url])
        let relative = Set(index.candidates.map { String($0.url.path.dropFirst(dir.url.path.count + 1)) })
        #expect(relative == ["big", "photo.jpg", "wrongtag/blob"])
        #expect(index.taggedCaches.map(\.url.lastPathComponent) == ["tagged"])
        #expect((index.taggedCaches.first?.bytes ?? 0) >= 2_000_000)
    }

    @Test func treeTotalsMatchIndependentSum() async throws {
        let dir = try TempDir()
        try dir.file("a/x", bytes: 1_500_000)
        try dir.file("a/b/y", bytes: 2_500_000)
        try dir.file("z", bytes: 1_200_000)
        try dir.file("tiny", bytes: 3)
        let a = try dir.file("hard", bytes: 1_000_000)
        #expect(link(a.path, dir.url.appendingPathComponent("a/hard2").path) == 0)
        let index = try await FileIndexBuilder(policy: dir.policy).build(roots: [dir.url])
        #expect(index.treeSizeBasis == .allocated)
        let tree = try #require(index.trees.first)
        #expect(tree.size == (try expectedAllocated(dir.url)))
        #expect(tree.children.first?.url.lastPathComponent == "a")
        #expect(tree.children.map(\.size) == tree.children.map(\.size).sorted(by: >))
        #expect(!tree.children.contains { $0.url.lastPathComponent == "tiny" })
        #expect(await FileIndexBuilder.allocatedSize(of: dir.url) == tree.size)
        #expect(
            await FileIndexBuilder.allocatedSize(of: dir.url.appendingPathComponent("z")) == Int64(
                try lstatOf(dir.url.appendingPathComponent("z")).st_blocks) * 512)
    }

    /// Serial and threaded walks must produce byte-identical results (candidates, trees, totals).
    @Test func threadedWalkMatchesSerial() async throws {
        let dir = try TempDir()
        // Wide enough to fill the 16-slot queue; nested enough to exercise roll-up.
        for i in 0..<30 {
            try dir.file("d\(i)/sub/f", bytes: 1_500_000)
            try dir.file("d\(i)/small", bytes: 10)
        }
        let a = try dir.file("shared", bytes: 2_000_000)
        try FileManager.default.createDirectory(
            at: dir.url.appendingPathComponent("elsewhere"), withIntermediateDirectories: true)
        #expect(link(a.path, dir.url.appendingPathComponent("elsewhere/twin").path) == 0)
        try dir.file(".git/objects/blob", bytes: 500_000)
        let serial = FileIndexBuilder(policy: dir.policy, threads: 1)
        let threaded = FileIndexBuilder(policy: dir.policy, threads: 4)
        let s = try await serial.build(roots: [dir.url])
        let t = try await threaded.build(roots: [dir.url])
        #expect(s.candidates.map { $0.url.path } == t.candidates.map { $0.url.path })
        #expect(s.candidates.map(\.reclaimableBytes) == t.candidates.map(\.reclaimableBytes))
        #expect(s.taggedCaches == t.taggedCaches)
        #expect(s.readErrors == t.readErrors)
        #expect(s.entriesSeen == t.entriesSeen)
        if treeSignature(s.trees) != treeSignature(t.trees) {
            Issue.record("SERIAL: \(treeSignature(s.trees))\nTHREADED: \(treeSignature(t.trees))")
        }
    }

    private func treeSignature(_ trees: [FolderNode]) -> String {
        trees.map { node in
            "\(node.url.path):\(node.size)|(" + node.children.map { treeSignature([$0]) }.joined(separator: ",") + ")"
        }.joined(separator: ";")
    }

    @Test func maxDepthLimitsTreeButNotTotals() async throws {
        let dir = try TempDir()
        try dir.file("a/b/c/d", bytes: 1_500_000)
        var builder = FileIndexBuilder(policy: dir.policy)
        builder.maxDepth = 1
        let tree = try #require(try await builder.build(roots: [dir.url]).trees.first)
        let a = try #require(tree.children.first)
        #expect(a.children.isEmpty)
        #expect(a.size == tree.size)
        #expect(tree.size >= 1_500_000)
    }

    @Test func symlinksAreNotFollowed() async throws {
        let dir = try TempDir()
        try dir.file("real", bytes: 10)
        try FileManager.default.createSymbolicLink(
            at: dir.url.appendingPathComponent("root"), withDestinationURL: URL(fileURLWithPath: "/"))
        let index = try await FileIndexBuilder(policy: dir.policy).build(roots: [dir.url])
        #expect(index.entriesSeen == 2)
        #expect(index.trees.first?.size == (try expectedAllocated(dir.url)))
    }

    @Test func progressCountsEntriesAndBytes() async throws {
        let dir = try TempDir()
        try dir.file("a/x", bytes: 1_500_000)
        try dir.file("y", bytes: 10)
        let progress = ScanProgress()
        let index = try await FileIndexBuilder(policy: dir.policy, progress: progress).build(roots: [dir.url])
        #expect(progress.files == index.entriesSeen)
        #expect(progress.bytes == index.trees.first?.size)
        #expect(!progress.currentFolder.isEmpty)
    }

    @Test func cancellationStopsTheWalk() async throws {
        let dir = try TempDir()
        for i in 0..<20 { try dir.file("f\(i)", bytes: 10) }
        let builder = FileIndexBuilder(policy: dir.policy, threads: 1)
        let task = Task { () throws -> FileIndex in
            withUnsafeCurrentTask { $0?.cancel() }
            return try await builder.build(roots: [dir.url])
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    /// The threaded walk stops all workers and throws when its cancellation flag is set.
    @Test func cancellationStopsTheThreadedWalk() async throws {
        let dir = try TempDir()
        for i in 0..<200 { for j in 0..<50 { try dir.file("d\(i)/f\(j)", bytes: 10) } }
        let builder = FileIndexBuilder(policy: dir.policy, threads: 4)
        let task = Task { () throws -> FileIndex in
            try await withTaskCancellationHandler(
                operation: {
                    try await builder.build(roots: [dir.url])
                }, onCancel: { builder.cancellation.cancel() })
        }
        try await Task.sleep(for: .milliseconds(20))
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    /// Worker threads cannot await the gate, so a paused threaded walk must hold at a directory
    /// boundary instead of reading ahead.
    @Test func threadedWalkHonoursThePauseGate() async throws {
        let dir = try TempDir()
        for i in 0..<30 { try dir.file("d\(i)/f", bytes: 10) }
        let gate = ScanPauseGate()
        gate.setPaused(true)
        var builder = FileIndexBuilder(policy: dir.policy, threads: 4)
        builder.pauseGate = gate
        let task = Task { try await builder.build(roots: [dir.url]) }
        try await Task.sleep(for: .milliseconds(200))
        #expect(builder.progress.files == 0)
        gate.setPaused(false)
        _ = try await task.value
        #expect(builder.progress.files > 0)
    }
}

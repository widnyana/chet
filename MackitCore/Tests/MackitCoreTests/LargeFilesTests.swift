import Foundation
import Testing

@testable import MackitCore

struct LargeFilesTests {
    private func setMTime(_ url: URL, daysAgo: Double) throws {
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-daysAgo * 86_400)], ofItemAtPath: url.path)
    }

    @Test func listsLargeAndOldFiles() throws {
        let dir = try TempDir()
        try dir.file("big.bin", bytes: 600_000)
        try dir.file("mid.bin", bytes: 400_000)
        let old = try dir.file("old.bin", bytes: 100_000)
        try dir.file("recent.bin", bytes: 100_000)
        try setMTime(old, daysAgo: 730)
        var scanner = LargeFileScanner(policy: dir.policy)
        scanner.minSize = 500_000
        scanner.minOldSize = 50_000
        let items = try scanner.scan([dir.url])
        #expect(items.map(\.url.lastPathComponent) == ["big.bin", "old.bin"])
        #expect(items.allSatisfy { $0.risk == .review && $0.mode == .trash })
    }

    @Test func folderTreeSumsAndSorts() throws {
        let dir = try TempDir()
        try dir.file("a/x", bytes: 1_000_000)
        try dir.file("a/b/y", bytes: 2_000_000)
        try dir.file("z", bytes: 1_000_000)
        let tree = try FolderTree.build(dir.url, policy: dir.policy)
        #expect(tree.size > 3_900_000 && tree.size < 4_200_000)
        #expect(tree.children.map(\.url.lastPathComponent) == ["a", "z"])
        let a = try #require(tree.children.first)
        #expect(a.children.map(\.url.lastPathComponent) == ["b", "x"])
    }

    @Test func folderTreeStopsAtMaxDepth() throws {
        let dir = try TempDir()
        try dir.file("a/b/c", bytes: 1_000)
        let tree = try FolderTree.build(dir.url, policy: dir.policy, maxDepth: 1)
        #expect(tree.children.map(\.url.lastPathComponent) == ["a"])
        #expect(tree.children.first?.children.isEmpty == true)
        #expect(tree.children.first?.size == tree.size)
    }
}

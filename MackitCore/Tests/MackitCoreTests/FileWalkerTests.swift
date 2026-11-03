import Foundation
import Testing

@testable import MackitCore

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

    @Test func hardLinksCountOnce() throws {
        let dir = try TempDir()
        let a = try dir.file("a", bytes: 1_000_000)
        #expect(link(a.path, dir.url.appendingPathComponent("b").path) == 0)
        let total = try FileWalker(policy: dir.policy).totalSize(dir.url)
        #expect(total >= 900_000 && total < 1_500_000)
    }
}

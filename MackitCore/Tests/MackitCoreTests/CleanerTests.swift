import Darwin
import Foundation
import Testing

@testable import MackitCore

struct CleanerTests {
    private func item(_ url: URL, _ mode: DeleteMode = .permanent) throws -> ScanItem {
        let stamp = try #require(FileStamp.read(url))
        return ScanItem(url: url, categoryID: "test", risk: .safe, mode: mode, reclaimableBytes: stamp.size, stamp: stamp)
    }

    private func cleaner(_ dir: TempDir) -> Cleaner {
        var cleaner = Cleaner(policy: dir.policy, log: AuditLog(url: dir.url.appendingPathComponent("audit.log")))
        let fakeTrash = dir.url.appendingPathComponent("FakeTrash")
        cleaner.trash = { url in
            try FileManager.default.createDirectory(at: fakeTrash, withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: url, to: fakeTrash.appendingPathComponent(url.lastPathComponent))
        }
        cleaner.isRunning = { _ in false }
        return cleaner
    }

    @Test func permanentItemIsRemoved() throws {
        let dir = try TempDir()
        let file = try dir.file("cache/x", bytes: 1000)
        let report = cleaner(dir).clean([try item(file)])
        #expect(report.results.first?.outcome == .removed(1000))
        #expect(report.freedBytes == 1000)
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    @Test func trashItemIsMovedToTrash() throws {
        let dir = try TempDir()
        let file = try dir.file("photos/x.jpg", bytes: 1000)
        let report = cleaner(dir).clean([try item(file, .trash)])
        #expect(report.results.first?.outcome == .trashed(1000))
        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(FileManager.default.fileExists(atPath: dir.url.appendingPathComponent("FakeTrash/x.jpg").path))
    }

    @Test func modifiedFileIsSkipped() throws {
        let dir = try TempDir()
        let file = try dir.file("cache/x", bytes: 1000)
        let scanned = try item(file)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-60)], ofItemAtPath: file.path)
        #expect(cleaner(dir).clean([scanned]).results.first?.outcome == .skipped(.changed))
        #expect(FileManager.default.fileExists(atPath: file.path))
    }

    @Test func fileReplacedBySymlinkIsSkipped() throws {
        let dir = try TempDir()
        let file = try dir.file("cache/x", bytes: 1000)
        let target = try dir.file("keep/important", bytes: 1000)
        let scanned = try item(file)
        try FileManager.default.removeItem(at: file)
        try FileManager.default.createSymbolicLink(at: file, withDestinationURL: target)
        #expect(cleaner(dir).clean([scanned]).results.first?.outcome == .skipped(.changed))
        #expect(FileManager.default.fileExists(atPath: target.path))
    }

    @Test func missingFileIsSkipped() throws {
        let dir = try TempDir()
        let file = try dir.file("cache/x", bytes: 1000)
        let scanned = try item(file)
        try FileManager.default.removeItem(at: file)
        #expect(cleaner(dir).clean([scanned]).results.first?.outcome == .skipped(.missing))
    }

    @Test func policyDeniedPathIsSkipped() throws {
        let dir = try TempDir()
        try dir.file("Library/Caches/a", bytes: 10)
        let caches = dir.url.appendingPathComponent("Library/Caches")
        #expect(cleaner(dir).clean([try item(caches)]).results.first?.outcome == .skipped(.policy))
        #expect(FileManager.default.fileExists(atPath: caches.path))
    }

    @Test func runningOwnerAppIsSkipped() throws {
        let dir = try TempDir()
        let file = try dir.file("cache/x", bytes: 1000)
        var cleaner = cleaner(dir)
        cleaner.owner = { _ in "com.test.app" }
        cleaner.isRunning = { $0 == "com.test.app" }
        #expect(cleaner.clean([try item(file)]).results.first?.outcome == .skipped(.appRunning))
        #expect(FileManager.default.fileExists(atPath: file.path))
    }

    @Test func failureDoesNotStopTheRest() throws {
        let dir = try TempDir()
        let locked = try dir.file("locked/x", bytes: 1000)
        let free = try dir.file("free/y", bytes: 1000)
        let lockedDir = locked.deletingLastPathComponent()
        let items = [try item(locked), try item(free)]
        #expect(chmod(lockedDir.path, 0o555) == 0)
        defer { chmod(lockedDir.path, 0o755) }
        let report = cleaner(dir).clean(items)
        guard case .failed = report.results[0].outcome else {
            Issue.record("expected failure, got \(report.results[0].outcome)")
            return
        }
        #expect(report.results[1].outcome == .removed(1000))
        #expect(FileManager.default.fileExists(atPath: locked.path))
    }
}

import Darwin
import Foundation
import Testing

@testable import ChetCore

struct CleanerTests {
    private func item(_ url: URL, _ mode: DeleteMode = .permanent) throws -> ScanItem {
        let stamp = try #require(FileStamp.read(url))
        return ScanItem(
            url: url, categoryID: "test", risk: .safe, mode: mode, reclaimableBytes: stamp.size, stamp: stamp)
    }

    private func adminItem(_ url: URL) throws -> ScanItem {
        let stamp = try #require(FileStamp.read(url))
        return ScanItem(
            url: url, categoryID: "system-caches", risk: .review, mode: .permanent,
            reclaimableBytes: stamp.size, stamp: stamp, requiresAdmin: true)
    }

    private func cleaner(_ dir: TempDir, dryRun: Bool = false) -> Cleaner {
        var cleaner = Cleaner(
            policy: dir.policy, log: AuditLog(url: dir.url.appendingPathComponent("audit.log")),
            dryRun: dryRun)
        let fakeTrash = dir.url.appendingPathComponent("FakeTrash")
        cleaner.trash = { url in
            try FileManager.default.createDirectory(at: fakeTrash, withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: url, to: fakeTrash.appendingPathComponent(url.lastPathComponent))
        }
        cleaner.isRunning = { _ in false }
        return cleaner
    }

    @Test func reportsLiveProgress() throws {
        let dir = try TempDir()
        let first = try dir.file("cache/a", bytes: 1000)
        let second = try dir.file("cache/b", bytes: 2000)
        let items = [try item(first), try item(second)]
        let sink = ProgressRecorder()
        let report = cleaner(dir, dryRun: true).clean(items) { sink.append($0) }
        let updates = sink.values
        #expect(updates.first?.processed == 0)
        #expect(updates.first?.total == 2)
        #expect(updates.first?.currentPath.hasSuffix("cache/a") == true)
        #expect(updates.last?.processed == 2)
        #expect(updates.last?.processedBytes == 3000)
        #expect(updates.last?.freedBytes == 3000)
        #expect(updates.last?.currentPath == "")
        #expect(updates.last?.isFinal == true)
        #expect(updates.first?.isFinal == false)
        #expect(updates.first?.currentIsDirectory == false)
        #expect(report.freedBytes == 3000)
    }

    @Test func reportsFolderProgress() throws {
        let dir = try TempDir()
        let folder = dir.url.appendingPathComponent("cache/folder")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let scanned = try item(folder)
        let sink = ProgressRecorder()
        _ = cleaner(dir, dryRun: true).clean([scanned]) { sink.append($0) }
        #expect(sink.values.first?.currentIsDirectory == true)
        #expect(sink.values.first?.currentPath.hasSuffix("cache/folder") == true)
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

    @Test func localStateIsNeverRemovedOrTrashed() throws {
        let dir = try TempDir()
        let cache = dir.url.appendingPathComponent("Development/app/.terragrunt-cache/a/b")
        try dir.text("Development/app/.terragrunt-cache/a/b/terraform.tfstate", "{}")
        for mode in [DeleteMode.permanent, .trash] {
            let report = cleaner(dir).clean([try item(cache, mode)])
            #expect(report.results.first?.outcome == .skipped(.localState))
            #expect(FileManager.default.fileExists(atPath: cache.appendingPathComponent("terraform.tfstate").path))
        }
    }

    @Test func backendConfigAloneDoesNotBlockCleanup() throws {
        let dir = try TempDir()
        let terraform = dir.url.appendingPathComponent("Development/app/.terraform")
        try dir.file("Development/app/.terraform/providers/x/bin", bytes: 1000)
        try dir.text("Development/app/.terraform/terraform.tfstate", "{}")
        let report = cleaner(dir).clean([try item(terraform)])
        #expect(report.results.first?.outcome != .skipped(.localState))
        #expect(!FileManager.default.fileExists(atPath: terraform.path))
    }

    @Test func modifiedFileIsSkipped() throws {
        let dir = try TempDir()
        let file = try dir.file("cache/x", bytes: 1000)
        let scanned = try item(file)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-60)], ofItemAtPath: file.path)
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

    @Test func dryRunPermanentReportsRemovedButKeepsFile() throws {
        let dir = try TempDir()
        let file = try dir.file("cache/x", bytes: 1000)
        let report = cleaner(dir, dryRun: true).clean([try item(file)])
        #expect(report.results.first?.outcome == .removed(1000))
        #expect(report.dryRun)
        #expect(report.freedBytes == 1000)
        #expect(FileManager.default.fileExists(atPath: file.path))
    }

    @Test func dryRunTrashReportsTrashedButKeepsFile() throws {
        let dir = try TempDir()
        let file = try dir.file("photos/x.jpg", bytes: 1000)
        let report = cleaner(dir, dryRun: true).clean([try item(file, .trash)])
        #expect(report.results.first?.outcome == .trashed(1000))
        #expect(FileManager.default.fileExists(atPath: file.path))
        #expect(!FileManager.default.fileExists(atPath: dir.url.appendingPathComponent("FakeTrash/x.jpg").path))
    }

    @Test func dryRunStillSkipsChangedFiles() throws {
        let dir = try TempDir()
        let file = try dir.file("cache/x", bytes: 1000)
        let scanned = try item(file)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-60)], ofItemAtPath: file.path)
        #expect(cleaner(dir, dryRun: true).clean([scanned]).results.first?.outcome == .skipped(.changed))
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

    @Test func adminItemGoesThroughTheHelper() throws {
        let dir = try TempDir()
        let file = try dir.file("Library/Caches/system/x", bytes: 1000)
        var worker = cleaner(dir)
        let visits = Visits()
        worker.privileged = { item in
            visits.append(item.url)
            return .removed(item.reclaimableBytes)
        }
        let report = worker.clean([try adminItem(file)])
        #expect(report.results.first?.outcome == .removed(1000))
        #expect(report.freedBytes == 1000)
        #expect(visits.value == [file])
        // The helper owns the removal; the cleaner itself never touches a root path.
        #expect(FileManager.default.fileExists(atPath: file.path))
    }

    @Test func adminItemWithoutHelperIsAPolicySkip() throws {
        let dir = try TempDir()
        let file = try dir.file("Library/Caches/system/x", bytes: 1000)
        #expect(cleaner(dir).clean([try adminItem(file)]).results.first?.outcome == .skipped(.policy))
        #expect(FileManager.default.fileExists(atPath: file.path))
    }

    @Test func adminItemUnderDryRunNeverCallsTheHelper() throws {
        let dir = try TempDir()
        let file = try dir.file("Library/Caches/system/x", bytes: 1000)
        var worker = cleaner(dir, dryRun: true)
        let visits = Visits()
        worker.privileged = { item in
            visits.append(item.url)
            return .removed(item.reclaimableBytes)
        }
        let report = worker.clean([try adminItem(file)])
        #expect(report.results.first?.outcome == .removed(1000))
        #expect(visits.value.isEmpty)
        #expect(FileManager.default.fileExists(atPath: file.path))
    }

    @Test func dryRunIsRecordedHonestly() throws {
        let dir = try TempDir()
        let file = try dir.file("cache/x", bytes: 1000)
        let logURL = dir.url.appendingPathComponent("audit.log")
        let report = Cleaner(policy: dir.policy, log: AuditLog(url: logURL), dryRun: true).clean([try item(file)])
        #expect(report.dryRun)
        #expect(report.results.first?.dryRun == true)
        let line = try #require(String(contentsOf: logURL, encoding: .utf8).split(separator: "\n").first)
        let entry = try JSONDecoder().decode(AuditLog.Entry.self, from: Data(line.utf8))
        #expect(entry.result == "dry-removed")
    }
}

private final class ProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [CleanProgress] = []

    var values: [CleanProgress] {
        lock.lock()
        defer { lock.unlock() }
        return items
    }

    func append(_ progress: CleanProgress) {
        lock.lock()
        items.append(progress)
        lock.unlock()
    }
}

private final class Visits: @unchecked Sendable {
    private let lock = NSLock()
    private var urls: [URL] = []

    var value: [URL] {
        lock.lock()
        defer { lock.unlock() }
        return urls
    }

    func append(_ url: URL) {
        lock.lock()
        urls.append(url)
        lock.unlock()
    }
}

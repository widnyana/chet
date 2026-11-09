import Foundation
import Testing

@testable import MackitCore

struct AuditLogTests {
    @Test func writesOneJSONLinePerItem() throws {
        let dir = try TempDir()
        let logURL = dir.url.appendingPathComponent("logs/clean.log")
        var cleaner = Cleaner(policy: dir.policy, log: AuditLog(url: logURL), dryRun: false)
        cleaner.isRunning = { _ in false }
        let a = try dir.file("cache/a", bytes: 100)
        let b = try dir.file("cache/b", bytes: 200)
        let items = try [a, b].map { url in
            let stamp = try #require(FileStamp.read(url))
            return ScanItem(
                url: url, categoryID: "test", risk: .safe, mode: .permanent, reclaimableBytes: stamp.size, stamp: stamp)
        }
        _ = cleaner.clean(items)
        let lines = try String(contentsOf: logURL, encoding: .utf8).split(separator: "\n")
        #expect(lines.count == 2)
        let entries = try lines.map { try JSONDecoder().decode(AuditLog.Entry.self, from: Data($0.utf8)) }
        #expect(entries.map(\.path) == [a.path, b.path])
        #expect(entries.map(\.bytes) == [100, 200])
        #expect(entries.map(\.category) == ["test", "test"])
        #expect(lines.allSatisfy { $0.contains("\"category\":\"test\"") })
        #expect(entries.allSatisfy { $0.mode == "permanent" && $0.result == "removed" && !$0.time.isEmpty })
    }

    @Test func appRowsCarryTheApplicationsCategory() throws {
        let dir = try TempDir()
        let logURL = dir.url.appendingPathComponent("logs/clean.log")
        AuditLog(url: logURL).append(
            category: "applications", path: "/Applications/Example.app", bytes: 10, mode: .trash,
            result: "trashed", dryRun: true)
        let line = try String(contentsOf: logURL, encoding: .utf8)
        let entry = try JSONDecoder().decode(AuditLog.Entry.self, from: Data(line.utf8))
        #expect(entry.category == "applications")
        #expect(entry.mode == "trash")
        #expect(entry.result == "dry-trashed")
    }

    @Test func legacyLineWithoutCategoryStillDecodes() throws {
        let line = #"{"bytes":1,"mode":"permanent","path":"/tmp/a","result":"removed","time":"2026-01-01T00:00:00Z"}"#
        let entry = try JSONDecoder().decode(AuditLog.Entry.self, from: Data(line.utf8))
        #expect(entry.category == nil)
    }

    @Test func skipReasonIsLogged() {
        #expect(CleanOutcome.skipped(.changed).logValue == "skipped:changed")
        #expect(CleanOutcome.failed("denied").logValue == "failed:denied")
    }
}

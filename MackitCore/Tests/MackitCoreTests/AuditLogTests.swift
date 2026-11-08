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
        #expect(entries.allSatisfy { $0.mode == "permanent" && $0.result == "removed" && !$0.time.isEmpty })
    }

    @Test func skipReasonIsLogged() {
        #expect(CleanOutcome.skipped(.changed).logValue == "skipped:changed")
        #expect(CleanOutcome.failed("denied").logValue == "failed:denied")
    }
}

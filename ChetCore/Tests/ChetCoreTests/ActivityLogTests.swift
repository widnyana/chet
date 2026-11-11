import Foundation
import Synchronization
import Testing

@testable import ChetCore

struct ActivityLogTests {
    private func decoded(_ url: URL) throws -> [[String: Any]] {
        let data = try Data(contentsOf: url)
        return try data.split(separator: 0x0A).map { line in
            try #require(JSONSerialization.jsonObject(with: Data(line)) as? [String: Any])
        }
    }

    private func fileSize(_ url: URL) throws -> Int {
        try Data(contentsOf: url).count
    }

    private func names(in directory: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasPrefix(ActivityLogLimits.prunePrefix) }
            .sorted()
    }

    @Test func sixteenDebugRecordsFlushTogether() throws {
        let dir = try TempDir()
        let url = dir.url.appendingPathComponent(ActivityLogLimits.baseName)
        let log = ActivityLog(url: url)
        for _ in 0..<15 {
            log.append(.debug, .launch, .launchStarted)
        }
        #expect(try fileSize(url) == 0)
        log.append(.debug, .launch, .launchStarted)
        #expect(try decoded(url).count == 16)
    }

    @Test func elapsedIntervalFlushesPendingWithoutTimer() throws {
        let dir = try TempDir()
        let url = dir.url.appendingPathComponent(ActivityLogLimits.baseName)
        let now = Mutex(Date(timeIntervalSince1970: 1_700_000_000))
        let log = ActivityLog(url: url, clock: { now.withLock { $0 } })
        log.append(.debug, .scan, .scanStarted)
        #expect(try fileSize(url) == 0)
        now.withLock { $0 = $0.addingTimeInterval(6) }
        log.append(.debug, .scan, .scanStarted)
        let lines = try decoded(url)
        #expect(lines.count == 2)
        #expect(lines.allSatisfy { $0["message"] as? String == LogMessage.scanStarted.rawValue })
    }

    @Test func oversizeRecordIsDroppedWithoutPartialLine() throws {
        let dir = try TempDir()
        let url = dir.url.appendingPathComponent(ActivityLogLimits.baseName)
        let log = ActivityLog(url: url)
        let longPath = try #require(RelativePath(String(repeating: "a", count: 2_100)))
        let field = try #require(LogField.path(.relativePath, longPath))
        log.append(.debug, .scan, .scanEvent, [field])
        log.append(.debug, .scan, .scanStarted)
        log.flush()
        let lines = try decoded(url)
        #expect(lines.count == 1)
        #expect(lines.first?["message"] as? String == LogMessage.scanStarted.rawValue)
        #expect(log.droppedRecords == 1)
        #expect(try fileSize(url) > 0)
    }

    @Test func rotationReplacesRotatedFileAndCapsBothNames() throws {
        let dir = try TempDir()
        let url = dir.url.appendingPathComponent(ActivityLogLimits.baseName)
        let rotated = dir.url.appendingPathComponent(ActivityLogLimits.rotatedName)
        let log = ActivityLog(url: url, maxBytes: 4_096, kept: 2)
        let longPath = try #require(RelativePath(String(repeating: "b", count: 180)))
        let field = try #require(LogField.path(.relativePath, longPath))
        for _ in 0..<40 {
            log.append(.info, .scan, .scanEvent, [field])
        }
        #expect(FileManager.default.fileExists(atPath: rotated.path))
        #expect(try fileSize(url) <= 4_096)
        #expect(try fileSize(rotated) <= 4_096)
        try Data().write(to: rotated)
        for _ in 0..<40 {
            log.append(.info, .scan, .scanEvent, [field])
        }
        #expect(try fileSize(rotated) > 0)
        #expect(
            try names(in: dir.url)
                == [ActivityLogLimits.baseName, ActivityLogLimits.rotatedName].sorted()
        )
    }

    @Test func unwritableDirectoryDegradesWithoutThrowing() throws {
        let dir = try TempDir()
        let url = dir.url.appendingPathComponent(ActivityLogLimits.baseName)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o500], ofItemAtPath: dir.url.path)
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o700], ofItemAtPath: dir.url.path)
        }
        let log = ActivityLog(url: url)
        #expect(!log.isAvailable)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func secondWriterReopensLivePathAfterOwnerRotation() throws {
        let dir = try TempDir()
        let url = dir.url.appendingPathComponent(ActivityLogLimits.baseName)
        let rotated = dir.url.appendingPathComponent(ActivityLogLimits.rotatedName)
        let owner = ActivityLog(url: url, maxBytes: 3_000, kept: 2)
        owner.append(.info, .launch, .launchStarted)
        let follower = ActivityLog(url: url, maxBytes: 3_000, kept: 2)
        #expect(follower.isAvailable)
        follower.append(.info, .settings, .settingsChanged, [.redacted(.settingsKey, .userName)])
        let shared = try decoded(url)
        #expect(shared.last?["session"] as? String == follower.sessionID)
        let longPath = try #require(RelativePath(String(repeating: "c", count: 180)))
        let field = try #require(LogField.path(.relativePath, longPath))
        for _ in 0..<30 {
            owner.append(.info, .scan, .scanEvent, [field])
        }
        #expect(FileManager.default.fileExists(atPath: rotated.path))
        follower.append(.info, .ui, .uiViewAppeared, [.redacted(.view, .userName)])
        let live = try decoded(url)
        #expect(live.last?["session"] as? String == follower.sessionID)
        #expect(live.filter { $0["session"] as? String == follower.sessionID }.count == 1)
    }

    @Test func everyLineCarriesSixKeys() throws {
        let dir = try TempDir()
        let url = dir.url.appendingPathComponent(ActivityLogLimits.baseName)
        let log = ActivityLog(url: url)
        log.append(.warn, .clean, .cleanSummary, [.count(.count, 3), .bytes(.bytes, 1_024)])
        log.append(.error, .storage, .storageEmptyTrash, [.flag(.ok, true)])
        log.flush()
        let lines = try decoded(url)
        #expect(lines.count == 2)
        for line in lines {
            #expect(
                Set(line.keys)
                    == ["time", "session", "level", "category", "message", "fields"])
            #expect(line["session"] as? String == log.sessionID)
            #expect(line["time"] is String)
            #expect(line["level"] is String)
            #expect(line["category"] is String)
            #expect(line["message"] is String)
            #expect(line["fields"] is [[String: Any]])
        }
    }
}

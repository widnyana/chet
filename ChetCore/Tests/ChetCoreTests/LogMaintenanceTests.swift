import Foundation
import Testing

@testable import ChetCore

/// Launch-time rotation of a stale crash file and retention pruning; the AppDelegate is a
/// thin caller over these, so the scenarios run under `swift test`.
struct LogMaintenanceTests {
    private func seed(_ dir: URL, name: String, content: String) throws {
        try Data(content.utf8).write(to: dir.appendingPathComponent(name))
    }

    private func seed(_ dir: URL, name: String, content: String, modified: Date) throws {
        try seed(dir, name: name, content: content)
        try FileManager.default.setAttributes(
            [.modificationDate: modified], ofItemAtPath: dir.appendingPathComponent(name).path)
    }

    @Test func rotateRenamesCrashFileWithTimestamp() async throws {
        let dir = try TempDir()
        try seed(dir.url, name: "crash.txt", content: "CHET CRASH\nsignal: SIGSEGV\n")
        let rotated = LogMaintenance.rotateStaleCrashReport(in: dir.url, now: { 1_700_000_000 })
        #expect(rotated)
        #expect(!FileManager.default.fileExists(atPath: dir.url.appendingPathComponent("crash.txt").path))
        #expect(
            FileManager.default.fileExists(atPath: dir.url.appendingPathComponent("crash-1700000000000.txt").path))
        let text = try String(
            contentsOf: dir.url.appendingPathComponent("crash-1700000000000.txt"), encoding: .utf8)
        #expect(text.contains("CHET CRASH"))
    }

    @Test func noStaleCrashFileRotatesNothing() async throws {
        let dir = try TempDir()
        #expect(!LogMaintenance.rotateStaleCrashReport(in: dir.url, now: { 1_700_000_000 }))
    }

    @Test func twoRotationsGetDistinctTimestampNames() async throws {
        let dir = try TempDir()
        var clock = 1_700_000_000.0
        try seed(dir.url, name: "crash.txt", content: "first")
        #expect(LogMaintenance.rotateStaleCrashReport(in: dir.url, now: { clock }))
        try seed(dir.url, name: "crash.txt", content: "again")
        clock += 90
        #expect(LogMaintenance.rotateStaleCrashReport(in: dir.url, now: { clock }))
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.url.path).sorted()
        #expect(names.contains("crash-1700000000000.txt"))
        #expect(names.contains("crash-1700000090000.txt"))
    }

    @Test func retentionKeepsNewestFive() async throws {
        let dir = try TempDir()
        for i in 0..<7 { try seed(dir.url, name: "crash-\(1_700_000_000 + i).txt", content: "c\(i)") }
        LogMaintenance.pruneCrashHistory(in: dir.url, kept: 5)
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.url.path).sorted()
        #expect(names.count == 5)
        #expect(!names.contains("crash-1700000000000.txt"))
        #expect(!names.contains("crash-1700000001.txt"))
        #expect(names.contains("crash-1700000006.txt"))
    }

    @Test func diagnosticReportsExcludedFromLogsRule() async throws {
        let dir = try TempDir()
        let logs = try dir.file("Library/Logs/DiagnosticReports/chet-2026-11-04.ips", bytes: 10)
        let scanner = RuleScanner(home: dir.url)
        let rule = try #require(Rule.catalog.first { $0.id == "logs" })
        let result = try await scanner.scan(rule)
        let scanned = result.items.map(\.url)
        #expect(!scanned.contains(logs))
        let chet = try dir.file("Library/Logs/chet/flight.current", bytes: 10)
        #expect(!scanned.contains(chet))
    }

    @Test func pruneKeepsNewestRotatedLogsAndReturnsCount() async throws {
        let dir = try TempDir()
        try seed(dir.url, name: "application-debug.log", content: "live")
        try seed(
            dir.url, name: "application-debug.1.log", content: "oldest",
            modified: Date(timeIntervalSince1970: 1_700_000_000))
        try seed(
            dir.url, name: "application-debug.2.log", content: "middle",
            modified: Date(timeIntervalSince1970: 1_700_000_100))
        try seed(
            dir.url, name: "application-debug.3.log", content: "newest",
            modified: Date(timeIntervalSince1970: 1_700_000_200))
        let retained = LogMaintenance.pruneLogs(
            in: dir.url, prefix: "application-debug.", suffix: ".log", kept: 2)
        #expect(retained == 2)
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.url.path).sorted()
        #expect(names == ["application-debug.2.log", "application-debug.3.log", "application-debug.log"])
        let live = try String(
            contentsOf: dir.url.appendingPathComponent("application-debug.log"), encoding: .utf8)
        #expect(live == "live")
    }

    @Test func pruneRemovesAllRotatedLogsWhenKeepingNone() async throws {
        let dir = try TempDir()
        try seed(dir.url, name: "application-debug.log", content: "live")
        for i in 1...3 {
            try seed(dir.url, name: "application-debug.\(i).log", content: "r\(i)")
        }
        let retained = LogMaintenance.pruneLogs(
            in: dir.url, prefix: "application-debug.", suffix: ".log", kept: 0)
        #expect(retained == 0)
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.url.path).sorted()
        #expect(names == ["application-debug.log"])
    }

    @Test func pruneOfActivityLogsLeavesCrashReports() async throws {
        let dir = try TempDir()
        try seed(dir.url, name: "application-debug.log", content: "live")
        try seed(dir.url, name: "application-debug.1.log", content: "rotated")
        try seed(dir.url, name: "crash-0001.txt", content: "crash")
        _ = LogMaintenance.pruneLogs(
            in: dir.url, prefix: "application-debug.", suffix: ".log", kept: 0)
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.url.path).sorted()
        #expect(names == ["application-debug.log", "crash-0001.txt"])
    }

    @Test func pruneCrashHistoryKeepsFiveRotatedNames() async throws {
        let dir = try TempDir()
        for i in 0..<7 {
            try seed(
                dir.url, name: "crash-\(1_700_000_000 + i).txt", content: "c\(i)",
                modified: Date(timeIntervalSince1970: TimeInterval(1_700_000_000 + i)))
        }
        let outcome: Void = LogMaintenance.pruneCrashHistory(in: dir.url, kept: 5)
        _ = outcome
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.url.path).sorted()
        #expect(names.count == 5)
        #expect(!names.contains("crash-1700000000.txt"))
        #expect(!names.contains("crash-1700000001.txt"))
        #expect(names.contains("crash-1700000006.txt"))
    }
}

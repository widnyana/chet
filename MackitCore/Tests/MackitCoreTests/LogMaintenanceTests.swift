import Foundation
import Testing

@testable import MackitCore

/// Launch-time rotation of a stale crash file and retention pruning; the AppDelegate is a
/// thin caller over these, so the scenarios run under `swift test`.
struct LogMaintenanceTests {
    private func seed(_ dir: URL, name: String, content: String) throws {
        try Data(content.utf8).write(to: dir.appendingPathComponent(name))
    }

    @Test func rotateRenamesCrashFileWithTimestamp() throws {
        let dir = try TempDir()
        try seed(dir.url, name: "crash.txt", content: "MACKIT CRASH\nsignal: SIGSEGV\n")
        let rotated = LogMaintenance.rotateStaleCrashReport(in: dir.url, now: { 1_700_000_000 })
        #expect(rotated)
        #expect(!FileManager.default.fileExists(atPath: dir.url.appendingPathComponent("crash.txt").path))
        #expect(
            FileManager.default.fileExists(atPath: dir.url.appendingPathComponent("crash-1700000000000.txt").path))
        let text = try String(
            contentsOf: dir.url.appendingPathComponent("crash-1700000000000.txt"), encoding: .utf8)
        #expect(text.contains("MACKIT CRASH"))
    }

    @Test func noStaleCrashFileRotatesNothing() throws {
        let dir = try TempDir()
        #expect(!LogMaintenance.rotateStaleCrashReport(in: dir.url, now: { 1_700_000_000 }))
    }

    @Test func twoRotationsGetDistinctTimestampNames() throws {
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

    @Test func retentionKeepsNewestFive() throws {
        let dir = try TempDir()
        for i in 0..<7 { try seed(dir.url, name: "crash-\(1_700_000_000 + i).txt", content: "c\(i)") }
        LogMaintenance.pruneCrashHistory(in: dir.url, kept: 5)
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.url.path).sorted()
        #expect(names.count == 5)
        #expect(!names.contains("crash-1700000000000.txt"))
        #expect(!names.contains("crash-1700000001.txt"))
        #expect(names.contains("crash-1700000006.txt"))
    }

    @Test func diagnosticReportsExcludedFromLogsRule() throws {
        let dir = try TempDir()
        let logs = try dir.file("Library/Logs/DiagnosticReports/Mackit-2026-11-04.ips", bytes: 10)
        let scanner = RuleScanner(home: dir.url)
        let rule = try #require(Rule.catalog.first { $0.id == "logs" })
        let result = try scanner.scan(rule)
        let scanned = result.items.map(\.url)
        #expect(!scanned.contains(logs))
        let mackit = try dir.file("Library/Logs/Mackit/flight.current", bytes: 10)
        #expect(!scanned.contains(mackit))
    }
}

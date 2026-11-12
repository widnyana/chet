import Foundation
import Testing

@testable import ChetCore

struct TrashLedgerTests {
    private func operation(_ name: String, date: Date = Date()) -> TrashOperation {
        TrashOperation(
            date: date,
            entries: [
                TrashOperation.Entry(
                    originalPath: "/Users/test/\(name)", trashedPath: "/Users/test/.Trash/\(name)",
                    bytes: 10, categoryID: "test")
            ])
    }

    @Test func operationsReadNewestFirst() throws {
        let dir = try TempDir()
        let ledger = TrashLedger(url: dir.url.appendingPathComponent("ledger.jsonl"))
        let first = operation("a", date: Date(timeIntervalSince1970: 1))
        let second = operation("b", date: Date(timeIntervalSince1970: 2))
        ledger.append(first)
        ledger.append(second)
        #expect(ledger.operations().map(\.id) == [second.id, first.id])
    }

    @Test func pruningKeepsTheNewestTen() throws {
        let dir = try TempDir()
        let ledger = TrashLedger(url: dir.url.appendingPathComponent("ledger.jsonl"))
        var ids: [UUID] = []
        for index in 0..<12 {
            let op = operation("\(index)", date: Date(timeIntervalSince1970: TimeInterval(index)))
            ids.append(op.id)
            ledger.append(op)
        }
        let operations = ledger.operations(limit: 20)
        #expect(operations.count == TrashLedger.keptOperations)
        #expect(operations.map(\.id) == Array(ids.suffix(10).reversed()))
    }

    @Test func defaultURLFollowsTheAuditLogPattern() {
        #expect(
            TrashLedger.defaultURL.path.hasSuffix("Library/Application Support/Chet/trash-ledger.jsonl"))
    }

    @Test func restoreMovesAVerifiedEntryBack() throws {
        let dir = try TempDir()
        let ledger = TrashLedger(url: dir.url.appendingPathComponent("ledger.jsonl"), home: dir.url)
        let original = try dir.file("cache/a", bytes: 10)
        let trashed = dir.url.appendingPathComponent("Trash/a")
        try FileManager.default.createDirectory(
            at: trashed.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: original, to: trashed)
        let op = TrashOperation(entries: [
            .init(originalPath: original.path, trashedPath: trashed.path, bytes: 10, categoryID: "test")
        ])
        let report = ledger.restore(op)
        #expect(report.restored == 1)
        #expect(report.unavailable.isEmpty)
        #expect(FileManager.default.fileExists(atPath: original.path))
    }

    @Test func restoreRefusesAMissingTrashCopy() throws {
        let dir = try TempDir()
        let ledger = TrashLedger(url: dir.url.appendingPathComponent("ledger.jsonl"), home: dir.url)
        let original = try dir.file("cache/a", bytes: 10)
        let trashed = dir.url.appendingPathComponent("Trash/a")
        try FileManager.default.createDirectory(
            at: trashed.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: original, to: trashed)
        try FileManager.default.removeItem(at: trashed)
        let op = TrashOperation(entries: [
            .init(originalPath: original.path, trashedPath: trashed.path, bytes: 10, categoryID: "test")
        ])
        let report = ledger.restore(op)
        #expect(report.restored == 0)
        #expect(report.unavailable.first?.reason == .trashedItemMissing)
        #expect(!FileManager.default.fileExists(atPath: original.path))
    }

    @Test func restoreRefusesAnOccupiedOriginal() throws {
        let dir = try TempDir()
        let ledger = TrashLedger(url: dir.url.appendingPathComponent("ledger.jsonl"), home: dir.url)
        let original = try dir.file("cache/a", bytes: 10)
        let trashed = dir.url.appendingPathComponent("Trash/a")
        try FileManager.default.createDirectory(
            at: trashed.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: original, to: trashed)
        try dir.file("cache/a", bytes: 10)
        let op = TrashOperation(entries: [
            .init(originalPath: original.path, trashedPath: trashed.path, bytes: 10, categoryID: "test")
        ])
        let report = ledger.restore(op)
        #expect(report.restored == 0)
        #expect(report.unavailable.first?.reason == .originalPathOccupied)
    }

    @Test func restoreRefusesAMissingParent() throws {
        let dir = try TempDir()
        let ledger = TrashLedger(url: dir.url.appendingPathComponent("ledger.jsonl"), home: dir.url)
        let original = try dir.file("cache/a", bytes: 10)
        let trashed = dir.url.appendingPathComponent("Trash/a")
        try FileManager.default.createDirectory(
            at: trashed.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: original, to: trashed)
        try FileManager.default.removeItem(at: original.deletingLastPathComponent())
        let op = TrashOperation(entries: [
            .init(originalPath: original.path, trashedPath: trashed.path, bytes: 10, categoryID: "test")
        ])
        let report = ledger.restore(op)
        #expect(report.restored == 0)
        #expect(report.unavailable.first?.reason == .parentMissing)
    }

    @Test func restorableEntriesExcludeAMissingTrashCopy() throws {
        let dir = try TempDir()
        let ledger = TrashLedger(url: dir.url.appendingPathComponent("ledger.jsonl"), home: dir.url)
        let original = try dir.file("cache/a", bytes: 10)
        let trashed = dir.url.appendingPathComponent("Trash/a")
        try FileManager.default.createDirectory(
            at: trashed.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: original, to: trashed)
        let op = TrashOperation(entries: [
            .init(originalPath: original.path, trashedPath: trashed.path, bytes: 10, categoryID: "test")
        ])
        #expect(ledger.restorableEntries(in: op).count == 1)
        try FileManager.default.removeItem(at: trashed)
        #expect(ledger.restorableEntries(in: op).isEmpty)
        let report = ledger.restore(op)
        #expect(report.unavailable.first?.reason == .trashedItemMissing)
        #expect(!FileManager.default.fileExists(atPath: original.path))
    }

    @Test func restorableOperationsOmitAnEmptyOperation() throws {
        let dir = try TempDir()
        let ledger = TrashLedger(url: dir.url.appendingPathComponent("ledger.jsonl"), home: dir.url)
        let original = try dir.file("cache/a", bytes: 10)
        let trashed = dir.url.appendingPathComponent("Trash/a")
        try FileManager.default.createDirectory(
            at: trashed.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: original, to: trashed)
        let restorable = TrashOperation(entries: [
            .init(originalPath: original.path, trashedPath: trashed.path, bytes: 10, categoryID: "test")
        ])
        let gone = TrashOperation(entries: [
            .init(
                originalPath: dir.url.appendingPathComponent("cache/b").path,
                trashedPath: dir.url.appendingPathComponent("Trash/b").path,
                bytes: 10, categoryID: "test")
        ])
        ledger.append(restorable)
        ledger.append(gone)
        #expect(ledger.restorableOperations().map(\.id) == [restorable.id])
    }
}

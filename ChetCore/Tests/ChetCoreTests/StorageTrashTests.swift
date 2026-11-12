import Foundation
import Testing

@testable import ChetCore

struct StorageTrashTests {
    private func entry(_ url: URL, bytes: Int64 = 1000) -> StorageEntry {
        StorageEntry(url: url, bytes: bytes)
    }

    private func trasher(
        _ dir: TempDir, dryRun: Bool = false, appFolders: [URL]? = nil
    ) -> StorageTrasher {
        var trasher = StorageTrasher(
            policy: dir.policy, appFolders: appFolders, dryRun: dryRun)
        let fakeTrash = dir.url.appendingPathComponent("FakeTrash")
        trasher.trash = { url in
            try FileManager.default.createDirectory(at: fakeTrash, withIntermediateDirectories: true)
            let destination = fakeTrash.appendingPathComponent(url.lastPathComponent)
            try FileManager.default.moveItem(at: url, to: destination)
            return destination
        }
        return trasher
    }

    @Test func trashesInsideHome() throws {
        let dir = try TempDir()
        let folder = dir.url.appendingPathComponent("Downloads/old")
        try dir.file("Downloads/old/a.txt", bytes: 10)
        let result = trasher(dir).trash([entry(folder)])
        #expect(result.moved.count == 1)
        #expect(result.freedBytes == 1000)
        #expect(result.failed.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: folder.path))
    }

    @Test func dryRunTouchesNothing() throws {
        let dir = try TempDir()
        let folder = dir.url.appendingPathComponent("Downloads/old")
        try dir.file("Downloads/old/a.txt", bytes: 10)
        let result = trasher(dir, dryRun: true).trash([entry(folder)])
        #expect(result.dryRun)
        #expect(result.moved.isEmpty)
        #expect(result.wouldMove.count == 1)
        #expect(result.freedBytes == 0)
        #expect(FileManager.default.fileExists(atPath: folder.path))
    }

    @Test func refusesProtectedHomeFolder() throws {
        let dir = try TempDir()
        let folder = dir.url.appendingPathComponent("Library/Keychains")
        try dir.file("Library/Keychains/login.keychain", bytes: 10)
        #expect(trasher(dir, dryRun: true).check(entry(folder)) == .denied("protected folder"))
        let result = trasher(dir, dryRun: true).trash([entry(folder)])
        #expect(result.refusal == .protectedFolder)
        #expect(result.wouldMove.isEmpty)
        #expect(result.failed.isEmpty)
    }

    @Test func refusedBatchMovesNothing() throws {
        let dir = try TempDir()
        let other = try TempDir()
        let file = try other.file("Downloads/old/a.txt", bytes: 10)
        let result = trasher(dir).trash([entry(file.deletingLastPathComponent())])
        #expect(result.refusal == .batchOutsideRoot)
        #expect(result.moved.isEmpty)
        #expect(FileManager.default.fileExists(atPath: file.path))
    }

    @Test func refusesSymlink() throws {
        let dir = try TempDir()
        let target = dir.url.appendingPathComponent("real")
        try dir.file("real/a.txt", bytes: 10)
        let link = dir.url.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        #expect(trasher(dir, dryRun: true).check(entry(link)) == .denied("symlink"))
    }

    @Test func missingEntryFailsWithoutStoppingTheRest() throws {
        let dir = try TempDir()
        let present = dir.url.appendingPathComponent("Downloads/present")
        try dir.file("Downloads/present/a.txt", bytes: 10)
        let missing = dir.url.appendingPathComponent("Downloads/gone")
        let result = trasher(dir).trash([entry(missing), entry(present)])
        #expect(result.moved.count == 1)
        #expect(result.failed.count == 1)
        #expect(result.failed.first?.reason == "missing")
    }

    @Test func appBundleInsideAppFolderIsAllowed() throws {
        let dir = try TempDir()
        let apps = dir.url.appendingPathComponent("Applications")
        try dir.text("Applications/Foo.app/Contents/Info.plist", "<plist/>")
        let bundle = apps.appendingPathComponent("Foo.app")
        #expect(trasher(dir, dryRun: true, appFolders: [apps]).check(entry(bundle)) == .allowed)
    }

    @Test func appBundleOutsideAppFolderIsRefused() throws {
        let dir = try TempDir()
        try dir.text("Downloads/Foo.app/Contents/Info.plist", "<plist/>")
        let bundle = dir.url.appendingPathComponent("Downloads/Foo.app")
        #expect(trasher(dir, dryRun: true).check(entry(bundle)) == .denied("app bundle"))
    }

    @Test func crumbKeepsThePathPrefix() {
        let stack = ["A", "B", "C"]
        #expect(StoragePath.trimmed(stack, to: 0).isEmpty)
        #expect(StoragePath.trimmed(stack, to: 1) == ["A"])
        #expect(StoragePath.trimmed(stack, to: 2) == ["A", "B"])
        #expect(StoragePath.trimmed(stack, to: 3) == stack)
        #expect(StoragePath.trimmed(stack, to: 9) == stack)
    }

    @Test func nestedEntriesMoveOnce() throws {
        let dir = try TempDir()
        let parent = dir.url.appendingPathComponent("Downloads/old")
        let child = parent.appendingPathComponent("inner")
        try dir.file("Downloads/old/inner/a.txt", bytes: 10)
        let result = trasher(dir, dryRun: true).trash([entry(child), entry(parent)])
        #expect(result.wouldMove.count == 1)
        #expect(result.wouldMove.first?.url == parent)
        #expect(result.failed.isEmpty)
    }

    @Test func trashWritesOneLedgerRowPerMovedItem() throws {
        let dir = try TempDir()
        let ledger = TrashLedger(url: dir.url.appendingPathComponent("ledger.jsonl"))
        let folder = dir.url.appendingPathComponent("Downloads/old")
        try dir.file("Downloads/old/a.txt", bytes: 10)
        var worker = trasher(dir)
        worker.ledger = ledger
        let result = worker.trash([entry(folder)])
        #expect(result.operationID != nil)
        let operations = ledger.operations()
        #expect(operations.count == 1)
        #expect(operations.first?.entries.first?.trashedPath.hasSuffix("old") == true)
    }

    @Test func dryRunWritesNoLedgerRow() throws {
        let dir = try TempDir()
        let ledger = TrashLedger(url: dir.url.appendingPathComponent("ledger.jsonl"))
        let folder = dir.url.appendingPathComponent("Downloads/old")
        try dir.file("Downloads/old/a.txt", bytes: 10)
        var worker = trasher(dir, dryRun: true)
        worker.ledger = ledger
        let result = worker.trash([entry(folder)])
        #expect(result.operationID == nil)
        #expect(ledger.operations().isEmpty)
    }
}

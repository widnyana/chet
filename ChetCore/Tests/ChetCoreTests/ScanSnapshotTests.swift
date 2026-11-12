import Foundation
import Testing

@testable import ChetCore

struct ScanSnapshotTests {
    private func stamp() -> FileStamp {
        FileStamp(
            inode: 1, size: 100, modified: Date(timeIntervalSince1970: 1_700_000_000),
            links: 1, isSymlink: false, isRegularFile: true, isDataless: false)
    }

    private func item(_ path: String, basis: SizeBasis) -> ScanItem {
        ScanItem(
            url: URL(fileURLWithPath: path), categoryID: "caches", risk: .safe, mode: .permanent,
            reclaimableBytes: 100, stamp: stamp(), ownerBundleID: "com.example",
            requiresAdmin: false, kind: "Rust target", sizeBasis: basis)
    }

    private func snapshot(date: Date = Date(timeIntervalSince1970: 1_700_000_000)) -> ScanSnapshot {
        let first = item("/Users/test/cache/a", basis: .allocated)
        let second = item("/Users/test/cache/b", basis: .reclaimable)
        let third = item("/Users/test/cache/c", basis: .allocated)
        return ScanSnapshot(
            date: date,
            scopeSummary: "Everything",
            categories: [
                .init(id: "caches", title: "Caches", items: [first, second]),
                .init(id: "logs", title: "Logs", items: [third]),
            ],
            groups: [
                "duplicates": [.init(keeper: first.url, itemURLs: [second.url])],
                "similar-photos": [.init(keeper: third.url, itemURLs: [])],
            ],
            coverage: CoverageReport(
                used: 1_000, scanned: 500,
                hidden: [.init(label: "Swap", bytes: 100, reason: "Swap in use")],
                excluded: [
                    .init(label: "/Users/test/Private", bytes: 50, reason: "Folder left out of the scan")
                ],
                unaccounted: 350))
    }

    @Test func roundTripKeepsEveryField() throws {
        let dir = try TempDir()
        let url = dir.url.appendingPathComponent("snapshot.json")
        let original = snapshot()
        ScanSnapshotStore(url: url).save(original)
        let loaded = try #require(ScanSnapshotStore(url: url).load())
        #expect(loaded == original)
    }

    @Test func corruptFileIsQuarantined() throws {
        let dir = try TempDir()
        let url = dir.url.appendingPathComponent("snapshot.json")
        try Data("not json".utf8).write(to: url)
        #expect(ScanSnapshotStore(url: url).load() == nil)
        let corrupt = url.appendingPathExtension("corrupt")
        #expect(try String(contentsOf: corrupt, encoding: .utf8) == "not json")
        #expect(try String(contentsOf: url, encoding: .utf8) == "not json")
    }

    @Test func unknownVersionIsQuarantined() throws {
        let dir = try TempDir()
        let url = dir.url.appendingPathComponent("snapshot.json")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshot())
        var object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["version"] = ScanSnapshot.currentVersion + 1
        try JSONSerialization.data(withJSONObject: object).write(to: url)
        #expect(ScanSnapshotStore(url: url).load() == nil)
        #expect(FileManager.default.fileExists(atPath: url.appendingPathExtension("corrupt").path))
    }

    @Test func secondSaveBacksUpTheFirst() throws {
        let dir = try TempDir()
        let url = dir.url.appendingPathComponent("snapshot.json")
        let store = ScanSnapshotStore(url: url)
        let first = snapshot(date: Date(timeIntervalSince1970: 1_700_000_000))
        let second = snapshot(date: Date(timeIntervalSince1970: 1_700_000_100))
        store.save(first)
        store.save(second)
        #expect(store.load() == second)
        let backup = try #require(ScanSnapshotStore(url: url.appendingPathExtension("bak")).load())
        #expect(backup == first)
    }

    @Test func missingFileLoadsNothing() throws {
        let dir = try TempDir()
        let url = dir.url.appendingPathComponent("snapshot.json")
        #expect(ScanSnapshotStore(url: url).load() == nil)
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(!FileManager.default.fileExists(atPath: url.appendingPathExtension("corrupt").path))
    }

    @Test func defaultURLFollowsTheAuditLogPattern() {
        #expect(
            ScanSnapshotStore.defaultURL.path.hasSuffix(
                "Library/Application Support/Chet/scan-snapshot.json"))
    }
}

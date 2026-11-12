import Foundation
import Testing

@testable import ChetCore

struct CoverageAccountingTests {
    private func capacity(total: Int64, free: Int64) -> VolumeCapacity {
        VolumeCapacity.make(name: "Startup disk", total: total, rawFree: free, importantFree: free)
    }

    private func otherSpace() -> OtherSpaceInfo {
        OtherSpaceInfo(
            volumes: [
                .init(name: "Data", role: "Data", size: 1_000),
                .init(name: "VM", role: "", size: 2_000),
            ],
            snapshots: 2,
            swapUsed: 500,
            folders: [
                .init(path: "/Users/test/Private", size: 300, reason: .user)
            ],
            cloudFolders: ["/Users/test/Library/Mobile Documents"])
    }

    @Test func bucketsCarryLabelsAndReasons() {
        let report = CoverageAccounting.measure(
            scannedBytes: 10_000, capacity: capacity(total: 20_000, free: 5_000),
            otherSpace: otherSpace())
        #expect(report.used == 15_000)
        #expect(report.scanned == 10_000)
        #expect(report.hidden.map(\.label) == ["Data", "VM", "Swap", "Snapshots"])
        #expect(report.hidden.map(\.bytes) == [1_000, 2_000, 500, 0])
        #expect(report.hidden.allSatisfy { !$0.reason.isEmpty })
        #expect(report.excluded.map(\.label) == ["/Users/test/Private", "/Users/test/Library/Mobile Documents"])
        #expect(report.excluded.map(\.bytes) == [300, 0])
        #expect(report.excluded.allSatisfy { !$0.reason.isEmpty })
        #expect(report.excluded.first?.reason == SpaceSkipReason.user.word)
        #expect(report.unaccounted == 15_000 - 10_000 - 3_500 - 300)
    }

    @Test func clampKeepsUnaccountedAtZero() {
        let report = CoverageAccounting.measure(
            scannedBytes: 20_000, capacity: capacity(total: 20_000, free: 5_000),
            otherSpace: otherSpace())
        #expect(report.unaccounted == 0)
        #expect(report.hidden.count == 4)
        #expect(report.excluded.count == 2)
        #expect(report.hidden.allSatisfy { $0.bytes >= 0 })
    }

    @Test func honestGapIsReportedAsANumber() {
        let report = CoverageAccounting.measure(
            scannedBytes: 1_000, capacity: capacity(total: 20_000, free: 5_000),
            otherSpace: OtherSpaceInfo())
        #expect(report.unaccounted == 14_000)
        #expect(report.hidden.isEmpty)
        #expect(report.excluded.isEmpty)
    }
}

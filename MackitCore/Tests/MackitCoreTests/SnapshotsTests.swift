import Testing

@testable import MackitCore

struct SnapshotsTests {
    @Test func parsesTmutilOutput() {
        let output = """
            Snapshots for disk /:
            com.apple.TimeMachine.2026-11-01-101500.local
            com.apple.TimeMachine.2026-11-02-090000.local
            com.example.other.snapshot
            """
        let snapshots = Snapshots.parse(output)
        #expect(snapshots.map(\.date) == ["2026-11-01-101500", "2026-11-02-090000"])
        #expect(snapshots.first?.name == "com.apple.TimeMachine.2026-11-01-101500.local")
    }

    @Test func emptyOutputGivesNoSnapshots() {
        #expect(Snapshots.parse("").isEmpty)
        #expect(Snapshots.parse("Snapshots for disk /:\n").isEmpty)
    }
}

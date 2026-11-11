import Foundation
import Testing

@testable import ChetCore

struct VerboseLogTests {
    @Test func flagParseTable() {
        let table: [(String?, Bool)] = [
            (nil, false),
            ("1", true),
            ("true", true),
            ("TRUE", true),
            ("yes", false),
            ("0", false),
            ("", false),
        ]
        for (raw, expected) in table {
            let environment = raw.map { ["CHET_VERBOSE": $0] } ?? [:]
            #expect(VerboseLog.isEnabled(environment: environment) == expected)
        }
    }
}

@Suite(.serialized)
struct VerboseLogSlotTests {
    @Test func nilSlotWritesNothing() throws {
        let dir = try TempDir()
        VerboseLog.install(nil)
        VerboseLog.event(.info, .launch, .launchStarted, .count(.files, 1))
        VerboseLog.flush()
        #expect(!VerboseLog.isInstalled)
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.url.path)
        #expect(names.isEmpty)
    }

    @Test func writerSlotEmitsOnlyWhileInstalled() throws {
        let dir = try TempDir()
        let clock = LogTestClock()
        let writer = ActivityLog(
            url: dir.url.appendingPathComponent(ActivityLogLimits.baseName),
            clock: { clock.now })
        defer {
            VerboseLog.install(nil)
            writer.close()
        }
        VerboseLog.install(writer)
        #expect(VerboseLog.isInstalled)
        VerboseLog.event(.info, .launch, .launchStarted, .count(.files, 1))
        VerboseLog.install(nil)
        VerboseLog.event(.info, .launch, .launchTerminated, .count(.files, 1))
        VerboseLog.flush()
        let text = try String(
            contentsOf: dir.url.appendingPathComponent(ActivityLogLimits.baseName), encoding: .utf8)
        #expect(text.split(separator: "\n").count == 1)
    }
}

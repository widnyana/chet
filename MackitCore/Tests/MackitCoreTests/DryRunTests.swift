import Foundation
import Testing

@testable import MackitCore

struct DryRunTests {
    @Test func truthyValues() {
        #expect(DryRun.parse("1"))
        #expect(DryRun.parse("true"))
        #expect(DryRun.parse("TRUE"))
        #expect(DryRun.parse(" True "))
    }

    @Test func falsyAndMalformedValues() {
        #expect(!DryRun.parse(nil))
        #expect(!DryRun.parse(""))
        #expect(!DryRun.parse("0"))
        #expect(!DryRun.parse("false"))
        #expect(!DryRun.parse("yes"))
        #expect(!DryRun.parse("DRY_RUN=1"))
    }

    @Test func envFileFoundWalkingUp() throws {
        let dir = try TempDir()
        let nested = dir.url.appendingPathComponent("a/b", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try "OTHER=x\nDRY_RUN=1\n".write(
            to: dir.url.appendingPathComponent(".env"), atomically: true, encoding: .utf8)
        #expect(DryRun.envFileValue(from: nested))
    }

    @Test func envFileExplicitFalseWins() throws {
        let dir = try TempDir()
        try "DRY_RUN=false\n".write(
            to: dir.url.appendingPathComponent(".env"), atomically: true, encoding: .utf8)
        #expect(!DryRun.envFileValue(from: dir.url))
    }

    @Test func envWithoutKeyIsFalse() throws {
        let dir = try TempDir()
        try "OTHER=x\n".write(
            to: dir.url.appendingPathComponent(".env"), atomically: true, encoding: .utf8)
        #expect(!DryRun.envFileValue(from: dir.url))
    }
}

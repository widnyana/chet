import Darwin
import Foundation
import Testing

@testable import ChetCore

/// The marker has to survive a SIGKILL from macOS, so it is a file, not a preference.
struct AccessAttemptTests {
    @Test func recordCreatesMarkerThatSurvives() throws {
        let dir = try TempDir()
        let url = dir.url.appendingPathComponent("Library/Application Support/chet/grant-attempted")
        #expect(!AccessAttempt.hasAttempted(url: url))
        #expect(AccessAttempt.record(url: url))
        #expect(AccessAttempt.hasAttempted(url: url))
        // Content is on disk, not buffered.
        #expect(try String(contentsOf: url, encoding: .utf8).contains("attempted"))
    }

    @Test func clearRemovesMarker() throws {
        let dir = try TempDir()
        let url = dir.url.appendingPathComponent("marker")
        #expect(AccessAttempt.record(url: url))
        AccessAttempt.clear(url: url)
        #expect(!AccessAttempt.hasAttempted(url: url))
    }

    @Test func recordFailsOnUnwritableDirectory() throws {
        let dir = try TempDir()
        let blocker = dir.url.appendingPathComponent("blocked")
        try Data("not a directory".utf8).write(to: blocker)
        #expect(!AccessAttempt.record(url: blocker.appendingPathComponent("marker")))
    }
}

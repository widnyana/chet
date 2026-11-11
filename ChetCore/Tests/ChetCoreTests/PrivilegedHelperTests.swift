import Foundation
import Testing

@testable import ChetCore

struct PrivilegedHelperTests {
    @Test func allowedChildOfAnInjectedRoot() throws {
        let dir = try TempDir()
        let file = try dir.file("a", bytes: 10)
        #expect(HelperGuard.refusal(path: file.path, roots: [dir.url.path]) == nil)
    }

    @Test func symlinkIsRefused() throws {
        let dir = try TempDir()
        let target = try dir.file("target", bytes: 10)
        let link = dir.url.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        #expect(HelperGuard.refusal(path: link.path, roots: [dir.url.path]) == "symlink")
    }

    @Test func pathOutsideTheRootsIsRefused() throws {
        let dir = try TempDir()
        let outside = try TempDir()
        let file = try outside.file("a", bytes: 10)
        #expect(HelperGuard.refusal(path: file.path, roots: [dir.url.path]) == "outside allowed roots")
    }

    @Test func rootItselfIsNotRemovable() throws {
        let dir = try TempDir()
        #expect(HelperGuard.refusal(path: dir.url.path, roots: [dir.url.path]) == "outside allowed roots")
    }

    @Test func directAppBundleInAnInjectedAppRootIsAllowed() throws {
        let root = try TempDir()
        let bundle = root.url.appendingPathComponent("Slides.app")
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        #expect(HelperGuard.refusal(path: bundle.path, appRoots: [root.url.path]) == nil)
    }

    @Test func appBundleContentsAreRefused() throws {
        let root = try TempDir()
        let bundle = root.url.appendingPathComponent("Slides.app")
        let contents = bundle.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        #expect(
            HelperGuard.refusal(path: contents.path, appRoots: [root.url.path]) == "not an app bundle")
    }

    @Test func nonBundleChildOfAnAppRootIsRefused() throws {
        let root = try TempDir()
        let notes = try root.file("notes", bytes: 10)
        #expect(
            HelperGuard.refusal(path: notes.path, appRoots: [root.url.path]) == "not an app bundle")
    }

    @Test func appRootItselfIsRefused() throws {
        let root = try TempDir()
        #expect(
            HelperGuard.refusal(path: root.url.path, appRoots: [root.url.path])
                == "outside allowed roots")
    }

    @Test func symlinkedAppBundleIsRefused() throws {
        let root = try TempDir()
        let target = root.url.appendingPathComponent("Slides.app")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let link = root.url.appendingPathComponent("Link.app")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        #expect(HelperGuard.refusal(path: link.path, appRoots: [root.url.path]) == "symlink")
    }

    @Test func chetItselfIsRefusedEvenAsADirectBundle() throws {
        let root = try TempDir()
        let bundle = root.url.appendingPathComponent("Chet.app")
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        #expect(
            HelperGuard.refusal(path: bundle.path, appRoots: [root.url.path]) == "not an app bundle")
    }

    @Test func systemPathsAreProtected() {
        #expect(HelperGuard.refusal(path: "/System/x") == "protected")
        #expect(HelperGuard.refusal(path: "/Library/Keychains/login.keychain-db") == "protected")
    }

    @Test func relativeAndTraversingPathsAreRefused() {
        #expect(HelperGuard.refusal(path: "relative") == "not absolute")
        #expect(HelperGuard.refusal(path: "") == "not absolute")
        #expect(HelperGuard.refusal(path: "/Library/Caches/../../System") == "path traversal")
    }

    @Test func missingChildIsReportedAsMissing() throws {
        let dir = try TempDir()
        #expect(
            HelperGuard.refusal(path: dir.url.appendingPathComponent("gone").path, roots: [dir.url.path])
                == "missing")
    }

    @Test func lifetimeIsClampedAndTheClockStartsOnFirstUse() {
        let clock = TestClock()
        var session = HelperSession(lifetime: 600, clock: { clock.now })
        #expect(session.remaining() == 600)
        let first = session.allow()
        #expect(first)
        clock.advance(599)
        let stillOpen = session.allow()
        #expect(stillOpen)
        clock.advance(1)
        let closed = session.allow()
        #expect(!closed)
        #expect(session.remaining() == 0)
        #expect(HelperSession(lifetime: 5).lifetime == 60)
        #expect(HelperSession(lifetime: 99_999).lifetime == 3600)
        #expect(HelperSession(lifetime: .infinity).lifetime == 600)
    }
}

/// A clock the test moves by hand, so the session deadline is exercised without waiting.
private final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current = Date(timeIntervalSince1970: 1_000_000)

    var now: Date {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    func advance(_ seconds: TimeInterval) {
        lock.lock()
        current += seconds
        lock.unlock()
    }
}

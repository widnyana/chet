import Foundation
import Testing

@testable import MackitCore

struct SafetyPolicyTests {
    let policy = SafetyPolicy(home: URL(fileURLWithPath: "/Users/test"))

    func verdict(_ path: String) -> Verdict { policy.isDeletable(URL(fileURLWithPath: path)) }

    @Test(arguments: [
        "/System/x",
        "/Users/test/Library/Keychains/login.keychain-db",
        "/Users/test/Library/Mobile Documents/x",
        "/Applications/Foo.app/Contents/x",
        "/Users/test/code/.git/config",
        "/Users/test/Library/Caches/../Keychains/x",
        "/Users/test/Library/Caches",
        "/Users/test",
        "/Users/test/Pictures/Photos Library.photoslibrary/database",
        "/Volumes/Ext/file",
    ])
    func denies(_ path: String) {
        #expect(verdict(path) != .allowed)
    }

    @Test(arguments: [
        "/Users/test/Library/Caches/com.foo/bar",
        "/Users/test/.Trash/file",
        "/Users/test/.Trash/Old.app",
        "/Volumes/Ext/.Trashes/501/file",
        "/Users/test/Library/Containers/com.apple.mail/Data/Library/Mail Downloads/a.pdf",
    ])
    func allows(_ path: String) {
        #expect(verdict(path) == .allowed)
    }

    @Test func deniesSymlink() throws {
        let dir = try TempDir()
        let target = try dir.file("Library/Caches/real", bytes: 10)
        let link = dir.url.appendingPathComponent("Library/Caches/link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        #expect(dir.policy.isDeletable(link) == .denied("symlink"))
        #expect(dir.policy.isDeletable(target) == .allowed)
    }
}

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
        "/Users/test/Library/Caches/com.example.app/blob",
        "/Users/test/Library/Caches/com.example.app",
        "/Volumes/Ext/.Trashes/501/file",
        "/Users/test/Library/Containers/com.apple.mail/Data/Library/Mail Downloads/a.pdf",
    ])
    func allows(_ path: String) {
        #expect(verdict(path) == .allowed)
    }

    /// No under-inclusion: everything the full policy allows, the scan gate allows too.
    @Test(arguments: [
        "/Users/test/Library/Caches/com.foo/bar",
        "/Users/test/.Trash/file",
        "/Users/test/.Trash/Old.app",
        "/Users/test/Library/Caches/com.example.app/blob",
        "/Users/test/Library/Caches/com.example.app",
        "/Volumes/Ext/.Trashes/501/file",
        "/Users/test/Library/Containers/com.apple.mail/Data/Library/Mail Downloads/a.pdf",
    ])
    func scanGateAllowsEverythingTheFullPolicyAllows(_ path: String) {
        let url = URL(fileURLWithPath: path)
        #expect(verdict(path) == .allowed)  // the fixture itself must hold, or the test lies
        #expect(policy.scanGateAllows(url, isSymlink: false, device: 1, parentDevice: 1))
    }

    /// Same denials as the full policy's bulk-visible string rules. Paths are walk-canonical
    /// (the gate's documented precondition); non-canonical forms are `isDeletable`'s to resolve.
    @Test(arguments: [
        "/System/x",
        "/Users/test/Library/Keychains/login.keychain-db",
        "/Users/test/Library/Mobile Documents/x",
        "/Applications/Foo.app/Contents/x",
        "/Users/test/code/.git/config",
        "/Users/test",
        "/Users/test/Pictures/Photos Library.photoslibrary/database",
        "/Volumes/Ext/file",
    ])
    func scanGateDeniesWhatTheFullPolicyDenies(_ path: String) {
        let url = URL(fileURLWithPath: path)
        #expect(verdict(path) != .allowed)  // the fixture itself must hold, or the test lies
        #expect(!policy.scanGateAllows(url, isSymlink: false, device: 1, parentDevice: 1))
    }

    @Test func scanGateDeniesSymlinksAndCrossDeviceEntries() {
        let url = URL(fileURLWithPath: "/Users/test/x")
        #expect(!policy.scanGateAllows(url, isSymlink: true, device: 1, parentDevice: 1))
        #expect(!policy.scanGateAllows(url, isSymlink: false, device: 2, parentDevice: 1))
        #expect(policy.scanGateAllows(url, isSymlink: false, device: 1, parentDevice: 1))
    }

    @Test func deniesRealAppBundleOnDisk() throws {
        let dir = try TempDir()
        try dir.file("Apps/Real.app/Contents/Info.plist", bytes: 10)
        try dir.file("Apps/Real.app/Contents/MacOS/Real", bytes: 10)
        try dir.file("Library/Caches/com.example.app/blob", bytes: 10)
        #expect(dir.policy.isDeletable(dir.url.appendingPathComponent("Apps/Real.app")) == .denied("app bundle"))
        #expect(
            dir.policy.isDeletable(dir.url.appendingPathComponent("Apps/Real.app/Contents/MacOS/Real"))
                == .denied("app bundle"))
        #expect(dir.policy.isDeletable(dir.url.appendingPathComponent("Library/Caches/com.example.app")) == .allowed)
    }

    @Test func deniesSymlink() throws {
        let dir = try TempDir()
        let target = try dir.file("Library/Caches/real", bytes: 10)
        let link = dir.url.appendingPathComponent("Library/Caches/link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        #expect(dir.policy.isDeletable(link) == .denied("symlink"))
        #expect(dir.policy.isDeletable(target) == .allowed)
    }

    // MARK: - external roots

    @Test func allowsPathUnderExternalRoot() throws {
        let dir = try TempDir()
        try dir.file("nix/var/nix/profiles/per-user/wid/a-profile", bytes: 100)
        let policy = SafetyPolicy(home: dir.url, externalRoots: [dir.url.appendingPathComponent("nix/var/nix/profiles").path])
        #expect(policy.isDeletable(dir.url.appendingPathComponent("nix/var/nix/profiles/per-user/wid/a-profile")) == .allowed)
    }

    @Test func deniesPathOutsideExternalRoot() throws {
        let dir = try TempDir()
        let policy = SafetyPolicy(home: dir.url, externalRoots: [dir.url.appendingPathComponent("nix/var/nix/profiles").path])
        #expect(policy.isDeletable(dir.url.appendingPathComponent("nix/var")) == .denied("outside home"))
    }

    @Test func externalRootStillDeniesSymlink() throws {
        let dir = try TempDir()
        try dir.file("nix/var/nix/profiles/real", bytes: 10)
        let link = dir.url.appendingPathComponent("nix/var/nix/profiles/link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: dir.url.appendingPathComponent("nix/var/nix/profiles/real"))
        let policy = SafetyPolicy(home: dir.url, externalRoots: [dir.url.appendingPathComponent("nix/var/nix/profiles").path])
        #expect(policy.isDeletable(link) == .denied("symlink"))
    }

    @Test func externalRootStillDeniesRealAppBundle() throws {
        let dir = try TempDir()
        try dir.file("nix/var/nix/profiles/Real.app/Contents/Info.plist", bytes: 10)
        try dir.file("nix/var/nix/profiles/Real.app/Contents/MacOS/Real", bytes: 10)
        let policy = SafetyPolicy(home: dir.url, externalRoots: [dir.url.appendingPathComponent("nix/var/nix/profiles").path])
        #expect(policy.isDeletable(dir.url.appendingPathComponent("nix/var/nix/profiles/Real.app")) == .denied("app bundle"))
    }

    // MARK: - excluded folders

    @Test func excludedFolderAndItsChildrenAreDenied() throws {
        let dir = try TempDir()
        try dir.file("Development/keep/project/main.tf", bytes: 10)
        let policy = SafetyPolicy(home: dir.url, excludedPaths: ["~/Development/keep"])
        let keep = dir.url.appendingPathComponent("Development/keep")
        #expect(policy.isDeletable(keep) == .denied("excluded folder"))
        #expect(policy.isDeletable(keep.appendingPathComponent("project/main.tf")) == .denied("excluded folder"))
        #expect(policy.isExcluded(keep.appendingPathComponent("project")))
    }

    @Test func exclusionMatchesWholePathPrefix() throws {
        let dir = try TempDir()
        try dir.file("Development/keeper/main.tf", bytes: 10)
        try dir.file("Development/keep/main.tf", bytes: 10)
        let policy = SafetyPolicy(home: dir.url, excludedPaths: [dir.url.appendingPathComponent("Development/keep").path])
        #expect(
            policy.isDeletable(dir.url.appendingPathComponent("Development/keeper/main.tf")) == .allowed)
        #expect(policy.isDeletable(dir.url.appendingPathComponent("Development/keep/main.tf")) != .allowed)
    }

    @Test func relativeExclusionIsIgnored() throws {
        let dir = try TempDir()
        try dir.file("Development/keepx/main.tf", bytes: 10)
        let policy = SafetyPolicy(home: dir.url, excludedPaths: ["Development/keep", ""])
        #expect(policy.excludedPaths.isEmpty)
        #expect(policy.isDeletable(dir.url.appendingPathComponent("Development/keepx/main.tf")) == .allowed)
    }
}

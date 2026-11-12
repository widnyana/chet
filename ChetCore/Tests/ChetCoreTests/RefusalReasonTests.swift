import Foundation
import Testing

@testable import ChetCore

struct RefusalReasonTests {
    @Test func everyRawValueRoundTrips() {
        for reason in RefusalReason.allCases {
            #expect(RefusalReason(rawValue: reason.rawValue) == reason)
        }
    }

    @Test func mountPointRawValueRoundTrips() {
        #expect(RefusalReason(rawValue: "mount point") == .mountPoint)
    }

    @Test func denialReasonNamesEachPathRule() throws {
        let dir = try TempDir()
        let policy = dir.policy

        try dir.file("Library/Caches/a", bytes: 10)
        #expect(policy.denialReason(for: dir.url.appendingPathComponent("Library/Caches")) == .containerFolder)

        try dir.file("Library/Keychains/login.keychain", bytes: 10)
        #expect(policy.denialReason(for: dir.url.appendingPathComponent("Library/Keychains")) == .protectedFolder)

        try dir.file("repo/.git/config", bytes: 10)
        #expect(policy.denialReason(for: dir.url.appendingPathComponent("repo/.git")) == .gitRepository)

        try dir.text("Downloads/Foo.app/Contents/Info.plist", "<plist/>")
        #expect(policy.denialReason(for: dir.url.appendingPathComponent("Downloads/Foo.app")) == .appBundle)

        try dir.file("Pictures/Photos.photoslibrary/db", bytes: 10)
        #expect(
            policy.denialReason(for: dir.url.appendingPathComponent("Pictures/Photos.photoslibrary"))
                == .photosLibrary)

        let outside = try TempDir()
        try outside.file("x", bytes: 10)
        #expect(policy.denialReason(for: outside.url.appendingPathComponent("x")) == .outsideHome)

        let target = try dir.file("real", bytes: 10)
        let link = dir.url.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        #expect(policy.denialReason(for: link) == .symlink)
    }

    @Test func excludedFolderIsNamed() throws {
        let dir = try TempDir()
        let skip = dir.url.appendingPathComponent("skip")
        let policy = SafetyPolicy(home: dir.url, excludedPaths: [skip.path])
        try dir.file("skip/a", bytes: 10)
        #expect(policy.denialReason(for: skip) == .excludedFolder)
    }

    @Test func isDeletableProjectsTheSameReason() throws {
        let dir = try TempDir()
        try dir.file("Library/Caches/a", bytes: 10)
        let caches = dir.url.appendingPathComponent("Library/Caches")
        #expect(dir.policy.isDeletable(caches) == .denied(RefusalReason.containerFolder.rawValue))
    }
}

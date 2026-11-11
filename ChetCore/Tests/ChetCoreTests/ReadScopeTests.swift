import Darwin
import Foundation
import Testing

@testable import ChetCore

@Suite struct ReadScopeTests {
    private func error(_ path: String, _ code: Int32, directory: Bool = false) -> WalkError {
        WalkError(url: URL(fileURLWithPath: path, isDirectory: directory), errno: code)
    }

    @Test func enotdirOnAFileIsRootFileAndNotBlocking() {
        let loose = error("/Users/example/notes.txt", ENOTDIR)
        #expect(ReadScope.classify(loose, roots: []) == .rootFile)
        #expect(ReadScope.blockingCount([loose], roots: []) == 0)
    }

    @Test func enoentAndEloopAreVanishedAndNotBlocking() {
        let root = "/Users/example/Library/Caches"
        for code in [ENOENT, ELOOP] {
            let gone = error("\(root)/com.example", code)
            #expect(ReadScope.classify(gone, roots: [root]) == .vanished)
            #expect(ReadScope.blockingCount([gone], roots: [root]) == 0)
        }
    }

    @Test func anErrorInsideACategoryRootIsBlocking() {
        let root = "/Users/example/Library/Caches"
        let inside = error("\(root)/com.example", EACCES)
        #expect(ReadScope.classify(inside, roots: [root]) == .categoryRoot)
        #expect(ReadScope.blockingCount([inside], roots: [root]) == 1)
        #expect(ReadScope.blockingCount([inside], roots: []) == 0)
    }

    @Test func theCategoryRootItselfIsBlocking() {
        let root = "/Users/example/Library/Caches"
        let failed = error(root, EACCES, directory: true)
        #expect(ReadScope.classify(failed, roots: [root]) == .categoryRoot)
        #expect(ReadScope.blockingCount([failed], roots: [root]) == 1)
    }

    @Test func systemProtectedPathsAreNotBlocking() {
        for path in [
            "/System/Library/PrivateFrameworks",
            "/private/var/db/diagnostics",
            "/.Spotlight-V100/Store-V2",
            "/.fseventsd",
            "/Library/Mail/V10",
        ] {
            let denied = error(path, EACCES, directory: true)
            #expect(ReadScope.classify(denied, roots: []) == .systemProtected)
            #expect(ReadScope.blockingCount([denied], roots: []) == 0)
        }
    }

    @Test func anotherUsersHomeIsOtherUserAndNotBlocking() {
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
        let path = home == "/Users/example" ? "/Users/someone/Documents" : "/Users/example/Documents"
        let denied = error(path, EACCES, directory: true)
        #expect(ReadScope.classify(denied, roots: []) == .otherUser)
        #expect(ReadScope.blockingCount([denied, denied], roots: []) == 0)
    }

    @Test func aHomePathOutsideEveryRootIsDiskMapOnly() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let denied = error(home.appendingPathComponent("Documents").path, EACCES, directory: true)
        #expect(ReadScope.classify(denied, roots: []) == .diskMapOnly)
        #expect(ReadScope.blockingCount([denied], roots: []) == 0)
    }

    @Test func aPathOutsideEveryScopeIsOther() {
        let denied = error("/Volumes/External/Archive", EACCES, directory: true)
        #expect(ReadScope.classify(denied, roots: []) == .other)
    }

    @Test func trailingSlashesDoNotChangeTheScope() {
        let root = "/Users/example/Library/Caches"
        let plain = error("\(root)/com.example", EACCES)
        let slashed = error("\(root)/com.example/", EACCES, directory: true)
        #expect(ReadScope.classify(plain, roots: ["\(root)/"]) == .categoryRoot)
        #expect(ReadScope.classify(slashed, roots: [root]) == .categoryRoot)
        #expect(
            ReadScope.classify(plain, roots: [root])
                == ReadScope.classify(slashed, roots: ["\(root)/"]))
    }

    @Test func dotSegmentsDoNotChangeTheScope() {
        let root = "/Users/example/Library/Caches"
        let meandering = error("/Users/example/Library/../Library/Caches/com.example", EACCES)
        #expect(ReadScope.classify(meandering, roots: [root]) == .categoryRoot)
        #expect(ReadScope.classify(meandering, roots: ["/Users/example/Library/../Library/Caches"]) == .categoryRoot)
    }

    @Test func aRootPrefixDoesNotMatchASiblingName() {
        let sibling = error("/Users/example/Library/Caches-old/file", EACCES)
        #expect(ReadScope.classify(sibling, roots: ["/Users/example/Library/Caches"]) != .categoryRoot)
    }
}

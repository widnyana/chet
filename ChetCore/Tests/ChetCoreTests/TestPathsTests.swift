import Darwin
import Foundation
import Testing

@testable import ChetCore

struct TestPathsTests {
    @Test func relativeRootIsRejected() {
        #expect(TestPaths.resolve(environment: ["CHET_UITEST_ROOT": "chet-uitest"]) == nil)
        #expect(TestPaths.resolve(environment: ["CHET_UITEST_ROOT": "tmp/chet-uitest"]) == nil)
        #expect(TestPaths.resolve(environment: ["CHET_UITEST_ROOT": ""]) == nil)
    }

    @Test func rootUnderHomeIsRejected() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        #expect(TestPaths.resolve(environment: ["CHET_UITEST_ROOT": home.path + "/chet-uitest"]) == nil)
        #expect(TestPaths.resolve(environment: ["CHET_UITEST_ROOT": home.path]) == nil)
    }

    @Test func parentTraversalEscapeIsRejected() {
        let escape = FileManager.default.temporaryDirectory.path + "/chet-uitest/../../../etc"
        #expect(TestPaths.resolve(environment: ["CHET_UITEST_ROOT": escape]) == nil)
        #expect(TestPaths.resolve(environment: ["CHET_UITEST_ROOT": "/tmp/../Users"]) == nil)
    }

    @Test func absoluteTemporaryRootResolves() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("chet-uitest-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let paths = try #require(TestPaths.resolve(environment: ["CHET_UITEST_ROOT": root.path]))
        #expect(paths.root == canonical(root))
        #expect(paths.logs == paths.root.appendingPathComponent("Logs", isDirectory: true))
    }

    @Test func makeScratchCreatesChildrenWithOwnerOnlyAccess() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("chet-uitest-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = try #require(TestPaths.makeScratch(environment: ["CHET_UITEST_ROOT": root.path]))
        #expect(paths.root == canonical(root))
        for directory in [paths.root] + paths.directories {
            var isDirectory: ObjCBool = false
            #expect(FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory))
            #expect(isDirectory.boolValue)
            let attributes = try FileManager.default.attributesOfItem(atPath: directory.path)
            #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o700)
        }
    }

    @Test func absentRootLeavesProductionPathsUnchanged() {
        #expect(TestPaths.resolve(environment: [:]) == nil)
        #expect(TestPaths.makeScratch(environment: [:]) == nil)
        let home = URL(fileURLWithPath: "/Users/example", isDirectory: true)
        let temporary = URL(fileURLWithPath: "/private/var/folders/aa/bb/T", isDirectory: true)
        let paths = TestPaths.production(home: home, temporary: temporary)
        #expect(paths.root == home)
        #expect(
            paths.applicationSupport == home.appendingPathComponent("Library/Application Support", isDirectory: true))
        #expect(paths.preferences == home.appendingPathComponent("Library/Preferences", isDirectory: true))
        #expect(paths.logs == home.appendingPathComponent("Library/Logs/chet", isDirectory: true))
        #expect(paths.caches == home.appendingPathComponent("Library/Caches", isDirectory: true))
        #expect(paths.trash == home.appendingPathComponent(".Trash", isDirectory: true))
        #expect(paths.temporary == temporary)
    }

    private func canonical(_ url: URL) -> URL {
        let path = url.path.withCString { realpath($0, nil) }.map { String(cString: $0) } ?? url.path
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    @Test func containerTemporaryInsideHomeIsAccepted() throws {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let container = home.appendingPathComponent(
            "Library/Containers/id.web.widnyana.chet.uitest.xctrunner/Data/tmp", isDirectory: true)
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: container) }
        let root = container.appendingPathComponent("chet-uitest-probe", isDirectory: true)
        let resolved = TestPaths.resolve(environment: [TestPaths.rootVariable: root.path])
        #expect(resolved != nil)
        #expect(resolved?.root.standardizedFileURL.path == root.standardizedFileURL.path)
    }
}

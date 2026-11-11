import Darwin
import XCTest

enum UITestError: Error, LocalizedError, CustomStringConvertible {
    case scratchRootCreationFailed
    case scratchRootOutsideTemporaryDirectory(String)
    case invalidPID(String)

    var errorDescription: String? { description }

    var description: String {
        switch self {
        case .scratchRootCreationFailed:
            "could not create a UI test scratch root"
        case .scratchRootOutsideTemporaryDirectory(let path):
            "UI test scratch root is outside /var/folders or /tmp: \(path)"
        case .invalidPID(let text):
            "app.pid does not contain a process id: \(text)"
        }
    }
}

@MainActor
class UITestCase: XCTestCase {
    private(set) var app: XCUIApplication!
    private(set) var scratchRoot: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        try MainActor.assumeIsolated {
            try SessionGuard.assertDryRun()
            try SessionGuard.assertNoUserInstance()
            try SessionGuard.assertNoHelper()
            scratchRoot = try Self.makeScratchRoot()
            let application = XCUIApplication()
            application.launchEnvironment["DRY_RUN"] = "1"
            application.launchEnvironment["CHET_UITEST_ROOT"] = scratchRoot.path
            application.launchEnvironment["CHET_UITEST_SESSION"] = "1"
            application.launchArguments = ["-ApplePersistenceIgnoreState", "YES"]
            app = application
        }
    }

    override func tearDownWithError() throws {
        let root = MainActor.assumeIsolated { () -> URL? in
            app?.terminate()
            return scratchRoot
        }
        if let root {
            print("chetUITests scratch root: \(root.path)")
            if FileManager.default.fileExists(atPath: root.path) {
                do {
                    try FileManager.default.removeItem(at: root)
                } catch {
                    XCTFail("could not remove scratch root \(root.path): \(error)")
                }
            }
            XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
        }
        try super.tearDownWithError()
    }

    private static func makeScratchRoot() throws -> URL {
        let template = FileManager.default.temporaryDirectory
            .appendingPathComponent("chet-uitest.XXXXXX", isDirectory: true).path
        var buffer = Array(template.utf8CString)
        guard mkdtemp(&buffer) != nil else {
            throw UITestError.scratchRootCreationFailed
        }
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        let root = URL(fileURLWithPath: String(decoding: bytes, as: UTF8.self), isDirectory: true)
        let path = root.standardizedFileURL.path
        let temporaryPrefixes = ["/var/folders/", "/private/var/folders/", "/tmp/", "/private/tmp/"]
        guard temporaryPrefixes.contains(where: path.hasPrefix) else {
            try? FileManager.default.removeItem(at: root)
            throw UITestError.scratchRootOutsideTemporaryDirectory(path)
        }
        return root
    }
}

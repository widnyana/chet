import AppKit
import Darwin
import XCTest

final class LaunchTests: UITestCase {
    private static let userPaths = [
        "Library/Application Support",
        "Library/Preferences",
        "Library/Logs/chet",
        "Library/Caches/id.web.widnyana.chet",
        ".Trash",
    ].map { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent($0).path }

    func testLaunchLeavesTheUserSessionUntouched() throws {
        let before = snapshotUserPaths()
        app.launch()
        XCTAssertTrue(
            app.wait(for: .runningForeground, timeout: 10),
            "chet did not reach a running state")
        let accessGate = app.descendants(matching: .any)["gate.continue"]
        if accessGate.waitForExistence(timeout: 2) {
            accessGate.click()
        }
        XCTAssertTrue(
            app.descendants(matching: .any)["home.scan"].waitForExistence(timeout: 10),
            "home.scan is missing")
        XCTAssertTrue(
            app.descendants(matching: .any)["home.scope"].waitForExistence(timeout: 10),
            "home.scope is missing")
        let pidURL = scratchRoot.appendingPathComponent("app.pid")
        XCTAssertTrue(
            waitForFile(pidURL, timeout: 10),
            "app.pid is missing from \(scratchRoot.path)")
        let pid = try readPID(pidURL)
        let running = try XCTUnwrap(
            NSRunningApplication(processIdentifier: pid),
            "no running application for pid \(pid)")
        let bundleIdentifier = try XCTUnwrap(running.bundleIdentifier)
        let bundleURL = try XCTUnwrap(running.bundleURL)
        let bundlePath = bundleURL.resolvingSymlinksInPath().path
        print("chetUITests launched \(bundleIdentifier) at \(bundlePath)")
        XCTAssertEqual(bundleIdentifier, "id.web.widnyana.chet")
        XCTAssertTrue(SessionGuard.isTestBuild(bundlePath), "launched \(bundlePath)")
        XCTAssertEqual(bundleURL.lastPathComponent, "chet.app")
        XCTAssertTrue(
            app.staticTexts["Preview only. Nothing is changed."].waitForExistence(timeout: 10),
            "the dry-run preview copy is missing")
        app.terminate()
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 5), "chet did not terminate")
        XCTAssertTrue(waitForExit(pid: pid, timeout: 5), "process \(pid) is still running")
        XCTAssertEqual(before, snapshotUserPaths())
    }

    private func snapshotUserPaths() -> [String: String] {
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .fileSizeKey, .isDirectoryKey]
        return Dictionary(
            uniqueKeysWithValues: Self.userPaths.map { path in
                let url = URL(fileURLWithPath: path)
                let values = try? url.resourceValues(forKeys: keys)
                let kind =
                    values == nil ? "missing" : (values?.isDirectory == true ? "directory" : "file")
                let size = values?.fileSize ?? -1
                let modified = values?.contentModificationDate?.timeIntervalSince1970 ?? -1
                return (path, "\(kind) \(size) \(modified)")
            })
    }

    private func waitForFile(_ url: URL, timeout: TimeInterval) -> Bool {
        wait(timeout: timeout) { FileManager.default.fileExists(atPath: url.path) }
    }

    private func waitForExit(pid: pid_t, timeout: TimeInterval) -> Bool {
        wait(timeout: timeout) { kill(pid, 0) == -1 && errno == ESRCH }
    }

    private func wait(timeout: TimeInterval, until condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return condition()
    }

    private func readPID(_ url: URL) throws -> pid_t {
        let text = try String(contentsOf: url, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let pid = pid_t(text), pid > 0 else {
            throw UITestError.invalidPID(text)
        }
        return pid
    }
}

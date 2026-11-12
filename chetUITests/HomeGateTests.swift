import ChetCore
import Foundation
import XCTest

final class HomeGateTests: UITestCase {
    @MainActor
    func testHomeRestsInPreviewWithOnlyAScanAvailable() throws {
        let driver = UITestDriver(app: app)
        try driver.requireFocus()
        try skipAccessGate(driver)
        let header = try driver.waitFor(AXSelector(["id=home.header"]), timeout: 20)
        XCTAssertTrue(header.value.contains("Clean up your Mac"), header.value)
        let preview = try? driver.resolve(AXSelector(["value=Preview only. Nothing is changed."]))
        XCTAssertNotNil(preview)
        let scan = try driver.waitFor(AXSelector(["id=home.scan"]), timeout: 20)
        XCTAssertEqual(scan.elementTypeName, "AXButton")
        XCTAssertTrue(scan.isEnabled)
        let scope = try driver.waitFor(AXSelector(["id=home.scope"]), timeout: 20)
        XCTAssertEqual(scope.elementTypeName, "AXButton")
        XCTAssertTrue(scope.isEnabled)
        assertMissing(AXSelector(["id=home.stop"]), driver)
        assertMissing(AXSelector(["id=home.pause"]), driver)
        assertMissing(AXSelector(["id=home.resume"]), driver)
        let probe = try AXProbe(root: scratchRoot)
        let headerTexts = try probe.texts(AXSelector(["id=home.header"]))
        XCTAssertTrue(headerTexts.contains { $0.contains("Clean up your Mac") }, "\(headerTexts)")
    }

    @MainActor
    func testEmptyScopeScanEndsAtHomeEmpty() throws {
        let driver = UITestDriver(app: app)
        try driver.requireFocus()
        try skipAccessGate(driver)
        let probe = try AXProbe(root: scratchRoot)
        let scan = try driver.waitFor(AXSelector(["id=home.scan"]), timeout: 20)
        try driver.requireFocus()
        scan.element.click()
        let empty = try driver.waitFor(AXSelector(["id=home.empty"]), timeout: 120)
        XCTAssertEqual(empty.elementTypeName, "AXStaticText")
        let idle = try driver.waitFor(AXSelector(["id=home.scan"]), timeout: 20)
        XCTAssertTrue(idle.isEnabled)
        assertMissing(AXSelector(["id=home.stop"]), driver)
        assertMissing(AXSelector(["id=home.pause"]), driver)
        assertMissing(AXSelector(["id=home.resume"]), driver)
        let texts = try probe.texts(AXSelector(["id=home.empty"]))
        XCTAssertTrue(
            texts.contains { $0.contains("Nothing to reclaim") && $0.contains("This Mac is tidy.") },
            "\(texts)")
    }

    @MainActor
    func testCoverageOpensTheSheet() throws {
        let driver = UITestDriver(app: app)
        try driver.requireFocus()
        try skipAccessGate(driver)
        try makeCacheFixture(count: 3)
        let scan = try driver.waitFor(AXSelector(["id=home.scan"]), timeout: 20)
        try driver.requireFocus()
        scan.element.click()
        _ = try driver.waitFor(AXSelector(["id=home.rescan"]), timeout: 180)
        let coverage = try driver.waitFor(AXSelector(["id=home.coverage"]), timeout: 30)
        try driver.requireFocus()
        coverage.element.click()
        let caption = try driver.waitFor(AXSelector(["Accounted for"]), timeout: 20)
        XCTAssertEqual(caption.elementTypeName, "AXStaticText")
        XCTAssertTrue(caption.value.contains(" of "), caption.value)
        try driver.requireFocus()
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(
            waitUntilMissing(AXSelector(["Accounted for"]), driver: driver, timeout: 10))
    }

    @MainActor
    func testRescanReturnsHomeToIdle() throws {
        let driver = UITestDriver(app: app)
        try driver.requireFocus()
        try skipAccessGate(driver)
        try makeCacheFixture(count: 3)
        let scan = try driver.waitFor(AXSelector(["id=home.scan"]), timeout: 20)
        try driver.requireFocus()
        scan.element.click()
        let rescan = try driver.waitFor(AXSelector(["id=home.rescan"]), timeout: 180)
        XCTAssertEqual(rescan.elementTypeName, "AXButton")
        XCTAssertTrue(rescan.isEnabled)
        try driver.requireFocus()
        rescan.element.click()
        let scope = try driver.waitFor(AXSelector(["id=home.scope"]), timeout: 120)
        XCTAssertTrue(scope.isEnabled)
        let idle = try driver.waitFor(AXSelector(["id=home.scan"]), timeout: 120)
        XCTAssertTrue(idle.isEnabled)
        assertMissing(AXSelector(["id=home.rescan"]), driver)
        assertMissing(AXSelector(["id=home.stop"]), driver)
        assertMissing(AXSelector(["id=home.pause"]), driver)
    }
}

extension UITestCase {
    @MainActor
    func skipAccessGate(_ driver: UITestDriver) throws {
        try driver.requireFocus()
        guard let gate = try? driver.resolve(AXSelector(["id=gate.continue"])) else { return }
        gate.element.click()
        _ = try driver.waitFor(AXSelector(["id=home.scan"]), timeout: 30)
    }

    @MainActor
    func assertMissing(
        _ selector: AXSelector, _ driver: UITestDriver, file: StaticString = #filePath,
        line: UInt = #line
    ) {
        do {
            let element = try driver.resolve(selector)
            XCTFail("expected no match, found \(element.description)", file: file, line: line)
        } catch {}
    }

    @MainActor
    func waitUntilMissing(
        _ selector: AXSelector, driver: UITestDriver, timeout: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if (try? driver.resolve(selector)) == nil { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return (try? driver.resolve(selector)) == nil
    }

    @MainActor
    func relaunch(environment: [String: String]) throws {
        app.terminate()
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 10))
        for (key, value) in environment {
            app.launchEnvironment[key] = value
        }
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))
        try FocusGuard.requireForeground(app)
    }

    @MainActor
    func selectSidebar(_ identifier: String, probe: AXProbe, driver: UITestDriver) throws {
        try driver.requireFocus()
        try probe.select(AXSelector(["id=\(identifier)"]))
    }

    func makeCacheFixture(count: Int) throws {
        let caches =
            scratchRoot
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Caches", isDirectory: true)
        for index in 0..<count {
            let folder = caches.appendingPathComponent(
                "com.example.chetuitest\(index)", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let file = folder.appendingPathComponent("payload.bin")
            XCTAssertTrue(
                FileManager.default.createFile(
                    atPath: file.path, contents: Data(repeating: 0x41, count: 4096)))
        }
    }

    func makeBulkFixture(folders: Int, filesPerFolder: Int) throws {
        let base = scratchRoot.appendingPathComponent("Bulk", isDirectory: true)
        let payload = Data(repeating: 0x42, count: 1024)
        for folderIndex in 0..<folders {
            let folder = base.appendingPathComponent("folder\(folderIndex)", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            for fileIndex in 0..<filesPerFolder {
                let file = folder.appendingPathComponent("file\(fileIndex).bin")
                XCTAssertTrue(
                    FileManager.default.createFile(atPath: file.path, contents: payload))
            }
        }
    }

    func probeValue(_ probe: AXProbe, _ selector: AXSelector) throws -> String? {
        let output = try probe.dump(selector)
        for line in output.stdout.split(separator: "\n") {
            guard let range = line.range(of: " value=") else { continue }
            return line[range.upperBound...].split(separator: " ").first.map(String.init)
        }
        return nil
    }
}

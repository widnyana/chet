import AppKit
import ChetCore
import Foundation
import XCTest

final class ScanStateTests: UITestCase {
    @MainActor
    func testDeniedAccessShowsTheGate() throws {
        let driver = UITestDriver(app: app)
        try driver.requireFocus()
        guard (try? driver.resolve(AXSelector(["id=gate.continue"]))) != nil else {
            throw XCTSkip("Full Disk Access is granted, so the denied gate cannot appear")
        }
        let title = try driver.waitFor(AXSelector(["id=gate.title"]), timeout: 20)
        XCTAssertEqual(title.elementTypeName, "AXStaticText")
        let open = try driver.waitFor(AXSelector(["id=gate.openSettings"]), timeout: 20)
        XCTAssertTrue(open.isEnabled)
        assertMissing(AXSelector(["id=home.scan"]), driver)
        let probe = try AXProbe(root: scratchRoot)
        let texts = try probe.texts(AXSelector(["id=gate.title"]))
        XCTAssertTrue(texts.contains { $0.contains("Chet needs Full Disk Access") }, "\(texts)")
    }

    @MainActor
    func testSkippedAccessShowsTheLimitedAccessBanner() throws {
        let driver = UITestDriver(app: app)
        try driver.requireFocus()
        guard let gate = try? driver.resolve(AXSelector(["id=gate.continue"])) else {
            throw XCTSkip("Full Disk Access is granted, so the limited-access banner cannot appear")
        }
        gate.element.click()
        _ = try driver.waitFor(AXSelector(["id=home.scan"]), timeout: 30)
        let banner = try driver.waitFor(
            AXSelector(["value=Limited access. Some folders are hidden."]), timeout: 20)
        XCTAssertEqual(banner.elementTypeName, "AXStaticText")
        let probe = try AXProbe(root: scratchRoot)
        let texts = try probe.texts(
            AXSelector(["value=Limited access. Some folders are hidden."]))
        XCTAssertFalse(texts.isEmpty)
        let scan = try driver.waitFor(AXSelector(["id=home.scan"]), timeout: 20)
        XCTAssertTrue(scan.isEnabled)
    }

    @MainActor
    func testScanPausesResumesAndStops() throws {
        let driver = UITestDriver(app: app)
        try driver.requireFocus()
        try skipAccessGate(driver)
        try makeBulkFixture(folders: 120, filesPerFolder: 120)
        let probe = try AXProbe(root: scratchRoot)
        let scan = try driver.waitFor(AXSelector(["id=home.scan"]), timeout: 20)
        try driver.requireFocus()
        scan.element.click()
        let stop = try driver.waitFor(AXSelector(["id=home.stop"]), timeout: 30)
        XCTAssertEqual(stop.elementTypeName, "AXButton")
        let runningTexts = try probe.texts(AXSelector(["id=home.header"]))
        XCTAssertTrue(
            runningTexts.contains { $0.contains("Scanning. Results appear as they finish.") },
            "\(runningTexts)")
        let pause = try driver.waitFor(AXSelector(["id=home.pause"]), timeout: 20)
        try driver.requireFocus()
        pause.element.click()
        let resume = try driver.waitFor(AXSelector(["id=home.resume"]), timeout: 20)
        XCTAssertEqual(resume.elementTypeName, "AXButton")
        assertMissing(AXSelector(["id=home.pause"]), driver)
        let pausedTexts = try probe.texts(AXSelector(["id=home.header"]))
        XCTAssertTrue(
            pausedTexts.contains { $0.contains("Scanning. Results appear as they finish.") },
            "\(pausedTexts)")
        try driver.requireFocus()
        resume.element.click()
        _ = try driver.waitFor(AXSelector(["id=home.pause"]), timeout: 20)
        let stopAgain = try driver.waitFor(AXSelector(["id=home.stop"]), timeout: 20)
        try driver.requireFocus()
        stopAgain.element.click()
        let idle = try driver.waitFor(AXSelector(["id=home.scan"]), timeout: 60)
        XCTAssertTrue(idle.isEnabled)
        assertMissing(AXSelector(["id=home.stop"]), driver)
        assertMissing(AXSelector(["id=home.pause"]), driver)
        assertMissing(AXSelector(["id=home.resume"]), driver)
    }

    @MainActor
    func testScanFinishesWithFixtureResults() throws {
        let driver = UITestDriver(app: app)
        try driver.requireFocus()
        try skipAccessGate(driver)
        try makeCacheFixture(count: 2)
        let probe = try AXProbe(root: scratchRoot)
        let scan = try driver.waitFor(AXSelector(["id=home.scan"]), timeout: 20)
        try driver.requireFocus()
        scan.element.click()
        let rescan = try driver.waitFor(AXSelector(["id=home.rescan"]), timeout: 180)
        XCTAssertEqual(rescan.elementTypeName, "AXButton")
        assertMissing(AXSelector(["id=home.empty"]), driver)
        assertMissing(AXSelector(["id=home.stop"]), driver)
        let headerTexts = try probe.texts(AXSelector(["id=home.header"]))
        XCTAssertTrue(headerTexts.contains { $0.contains("can be reclaimed") }, "\(headerTexts)")
        XCTAssertTrue(headerTexts.contains { $0.contains("1 category") }, "\(headerTexts)")
    }

    @MainActor
    func testSidebarSelectMovesBetweenDestinations() throws {
        let driver = UITestDriver(app: app)
        try driver.requireFocus()
        try skipAccessGate(driver)
        let probe = try AXProbe(root: scratchRoot)
        let overviewTexts = try probe.texts(AXSelector(["id=sidebar.overview"]))
        XCTAssertEqual(overviewTexts, ["Home"])
        try selectSidebar("sidebar.tweaks", probe: probe, driver: driver)
        _ = try driver.waitFor(AXSelector(["id=tweaks.page"]), timeout: 60)
        XCTAssertEqual(try probe.texts(AXSelector(["id=sidebar.tweaks"])), ["Tweaks"])
        try selectSidebar("sidebar.overview", probe: probe, driver: driver)
        let header = try driver.waitFor(AXSelector(["id=home.header"]), timeout: 20)
        XCTAssertTrue(header.value.contains("Clean up your Mac"))
    }

    @MainActor
    func testScanScopeAddsAndRemovesOneFolder() throws {
        let driver = UITestDriver(app: app)
        try driver.requireFocus()
        try skipAccessGate(driver)
        let scope = try driver.waitFor(AXSelector(["id=home.scope"]), timeout: 20)
        try driver.requireFocus()
        scope.element.click()
        _ = try driver.waitFor(AXSelector(["id=scan.scope"]), timeout: 20)
        let add = try driver.waitFor(AXSelector(["id=scan.scope.add"]), timeout: 20)
        try driver.requireFocus()
        add.element.click()
        let choose = app.buttons["Scan This Folder"]
        XCTAssertTrue(choose.waitForExistence(timeout: 10))
        try driver.requireFocus()
        app.typeKey("g", modifierFlags: [.command, .shift])
        XCTAssertTrue(app.staticTexts["Go to the folder:"].waitForExistence(timeout: 10))
        app.typeText(scratchRoot.path)
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(choose.waitForExistence(timeout: 10))
        choose.click()
        let remove = try driver.waitFor(AXSelector(["id=scan.scope.remove.0"]), timeout: 20)
        XCTAssertEqual(remove.elementTypeName, "AXButton")
        XCTAssertTrue(remove.isEnabled)
        try driver.requireFocus()
        remove.element.click()
        XCTAssertTrue(
            waitUntilMissing(AXSelector(["id=scan.scope.remove.0"]), driver: driver, timeout: 20))
        let cancel = try driver.waitFor(AXSelector(["id=scan.scope.cancel"]), timeout: 20)
        try driver.requireFocus()
        cancel.element.click()
        XCTAssertTrue(waitUntilMissing(AXSelector(["id=scan.scope"]), driver: driver, timeout: 20))
        let idle = try driver.waitFor(AXSelector(["id=home.scan"]), timeout: 20)
        XCTAssertTrue(idle.isEnabled)
        assertMissing(AXSelector(["id=home.stop"]), driver)
    }
}

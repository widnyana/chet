import ChetCore
import Foundation
import XCTest

final class BatchGuardUITests: UITestCase {
    @MainActor
    func testLegitimateBatchIsAcceptedAndDryRunKeepsEveryFile() throws {
        let driver = UITestDriver(app: app)
        try driver.requireFocus()
        try skipAccessGate(driver)
        try makeCacheFixture(count: 3)
        let scan = try driver.waitFor(AXSelector(["id=home.scan"]), timeout: 20)
        try driver.requireFocus()
        scan.element.click()
        _ = try driver.waitFor(AXSelector(["id=home.rescan"]), timeout: 240)
        let clean = try driver.waitFor(AXSelector(["role=AXButton", "Clean selected"]), timeout: 20)
        try driver.requireFocus()
        clean.element.click()
        let notice = try? driver.resolve(
            AXSelector(["value=Preview only. Nothing will be removed."]))
        XCTAssertNotNil(notice)
        let delete = try driver.waitFor(AXSelector(["role=AXButton", "Delete"]), timeout: 20)
        try driver.requireFocus()
        delete.element.click()
        let summary = try driver.waitFor(
            AXSelector(["3 of 3 items would be cleaned"]), timeout: 120)
        XCTAssertEqual(summary.elementTypeName, "AXStaticText")
        let done = try driver.waitFor(AXSelector(["role=AXButton", "Done"]), timeout: 20)
        try driver.requireFocus()
        done.element.click()
        XCTAssertTrue(
            waitUntilMissing(AXSelector(["role=AXButton", "Done"]), driver: driver, timeout: 20))
        let caches = scratchRoot.appendingPathComponent("Library/Caches", isDirectory: true)
        for index in 0..<3 {
            let file = caches.appendingPathComponent("com.example.chetuitest\(index)/payload.bin")
            XCTAssertTrue(FileManager.default.fileExists(atPath: file.path), file.path)
        }
    }
}

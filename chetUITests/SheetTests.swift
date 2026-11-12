import ChetCore
import Foundation
import XCTest

final class SheetTests: UITestCase {
    private static let gatedTweakID = "appearance.autohide-menu-bar"

    @MainActor
    func testCleanConfirmCancelLeavesTheSelectionAlone() throws {
        let driver = UITestDriver(app: app)
        try openCleanConfirm(driver, items: 3)
        let notice = try? driver.resolve(
            AXSelector(["value=Preview only. Nothing will be removed."]))
        XCTAssertNotNil(notice)
        let check = try? driver.resolve(
            AXSelector([
                "value=Every item would be checked again before removal. Files that changed would be left alone."
            ]))
        XCTAssertNotNil(check)
        let cancel = try driver.waitFor(AXSelector(["role=AXButton", "Cancel"]), timeout: 20)
        try driver.requireFocus()
        cancel.element.click()
        XCTAssertTrue(
            waitUntilMissing(AXSelector(["role=AXButton", "Cancel"]), driver: driver, timeout: 20))
        _ = try driver.waitFor(AXSelector(["id=home.rescan"]), timeout: 20)
        assertMissing(AXSelector(["id=home.stop"]), driver)
    }

    @MainActor
    func testCleanConfirmClosesOnEscape() throws {
        let driver = UITestDriver(app: app)
        try openCleanConfirm(driver, items: 3)
        _ = try driver.waitFor(AXSelector(["role=AXButton", "Cancel"]), timeout: 20)
        try driver.requireFocus()
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(
            waitUntilMissing(AXSelector(["role=AXButton", "Cancel"]), driver: driver, timeout: 20))
        _ = try driver.waitFor(AXSelector(["id=home.rescan"]), timeout: 20)
    }

    @MainActor
    func testCleanSheetStaysOpenWhileCleaning() throws {
        let driver = UITestDriver(app: app)
        try openCleanConfirm(driver, items: 2500)
        let clean = try driver.waitFor(AXSelector(["role=AXButton", "Delete"]), timeout: 20)
        try driver.requireFocus()
        clean.element.click()
        _ = try driver.waitFor(AXSelector(["value=Simulating clean"]), timeout: 60)
        try driver.requireFocus()
        app.typeKey(.escape, modifierFlags: [])
        let cleaning = try? driver.resolve(AXSelector(["value=Simulating clean"]))
        let finished = try? driver.resolve(AXSelector(["value=Dry run complete"]))
        XCTAssertTrue(
            cleaning != nil || finished != nil,
            "Escape closed the clean sheet while the clean was running")
        let done = try driver.waitFor(AXSelector(["role=AXButton", "Done"]), timeout: 120)
        try driver.requireFocus()
        done.element.click()
        XCTAssertTrue(waitUntilMissing(AXSelector(["role=AXButton", "Done"]), driver: driver, timeout: 20))
    }

    @MainActor
    func testCleanCancelStopsThePass() throws {
        let driver = UITestDriver(app: app)
        try openCleanConfirm(driver, items: 2500)
        let clean = try driver.waitFor(AXSelector(["role=AXButton", "Delete"]), timeout: 20)
        try driver.requireFocus()
        clean.element.click()
        _ = try driver.waitFor(AXSelector(["value=Simulating clean"]), timeout: 60)
        let cancel = try driver.waitFor(AXSelector(["id=clean.cancel"]), timeout: 20)
        XCTAssertTrue(cancel.isEnabled)
        try driver.requireFocus()
        cancel.element.click()
        _ = try driver.waitFor(AXSelector(["value=Dry run complete"]), timeout: 120)
        assertMissing(AXSelector(["id=clean.cancel"]), driver)
    }

    @MainActor
    func testRevertDialogStaysHiddenWithoutTheHook() throws {
        let driver = UITestDriver(app: app)
        try openTweakDetails(driver)
        assertMissing(AXSelector(["role=AXButton", "Revert"]), driver)
        assertMissing(AXSelector(["role=AXButton", "Revert last change"]), driver)
    }

    @MainActor
    func testRevertDialogNeedsThePreviewHook() throws {
        let driver = UITestDriver(app: app)
        try relaunch(environment: ["CHET_TWEAK_PREVIEW": "revert"])
        let probe = try AXProbe(root: scratchRoot)
        try openTweakDetails(driver, probe: probe)
        let revert = try driver.waitFor(AXSelector(["role=AXButton", "Revert"]), timeout: 20)
        XCTAssertTrue(revert.isEnabled)
        let control = AXSelector(["id=tweak.toggle.\(Self.gatedTweakID)"])
        let before = try probeValue(probe, control)
        XCTAssertNotNil(before)
        let cancel = try driver.waitFor(AXSelector(["role=AXButton", "Cancel"]), timeout: 20)
        try driver.requireFocus()
        cancel.element.click()
        XCTAssertTrue(waitUntilMissing(AXSelector(["role=AXButton", "Revert"]), driver: driver, timeout: 20))
        XCTAssertEqual(try probeValue(probe, control), before)
        let history = scratchRoot.appendingPathComponent("Application Support/Chet/tweaks.log")
        XCTAssertFalse(FileManager.default.fileExists(atPath: history.path))
    }

    @MainActor
    func testTrashHistoryOffersOnlyRestorableOperations() throws {
        let driver = UITestDriver(app: app)
        let restorableID = "11111111-1111-1111-1111-111111111111"
        let goneID = "22222222-2222-2222-2222-222222222222"
        let trashed = scratchRoot.appendingPathComponent("Trash/keep.txt")
        try FileManager.default.createDirectory(
            at: trashed.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("keep".utf8).write(to: trashed)
        let original = scratchRoot.appendingPathComponent("Library/Caches/keep.txt")
        try FileManager.default.createDirectory(
            at: original.deletingLastPathComponent(), withIntermediateDirectories: true)
        let goneTrashed = scratchRoot.appendingPathComponent("Trash/gone.txt")
        let goneOriginal = scratchRoot.appendingPathComponent("Library/Caches/gone.txt")
        try seedTrashLedger([
            (restorableID, trashed, original),
            (goneID, goneTrashed, goneOriginal),
        ])
        try relaunch(environment: [:])
        try driver.requireFocus()
        try skipAccessGate(driver)
        try makeCacheFixture(count: 1)
        let scan = try driver.waitFor(AXSelector(["id=home.scan"]), timeout: 20)
        try driver.requireFocus()
        scan.element.click()
        _ = try driver.waitFor(AXSelector(["id=home.rescan"]), timeout: 240)
        let probe = try AXProbe(root: scratchRoot)
        try selectSidebar("sidebar.disk-map", probe: probe, driver: driver)
        _ = try driver.waitFor(AXSelector(["id=storage.ledger.header"]), timeout: 20)
        let restore = try driver.waitFor(AXSelector(["id=storage.restore"]), timeout: 20)
        XCTAssertFalse(restore.isEnabled)
    }

    private func seedTrashLedger(_ operations: [(id: String, trashed: URL, original: URL)]) throws {
        let directory = scratchRoot.appendingPathComponent("Application Support/Chet", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        var data = Data()
        for operation in operations {
            let record = TrashOperation(
                id: UUID(uuidString: operation.id)!,
                date: Date(timeIntervalSince1970: 1_700_000_000),
                entries: [
                    TrashOperation.Entry(
                        originalPath: operation.original.path, trashedPath: operation.trashed.path,
                        bytes: 10, categoryID: "test")
                ])
            data.append(try encoder.encode(record))
            data.append(0x0A)
        }
        try data.write(to: directory.appendingPathComponent("trash-ledger.jsonl"))
    }

    @MainActor
    private func openCleanConfirm(_ driver: UITestDriver, items: Int) throws {
        try driver.requireFocus()
        try skipAccessGate(driver)
        try makeCacheFixture(count: items)
        let scan = try driver.waitFor(AXSelector(["id=home.scan"]), timeout: 20)
        try driver.requireFocus()
        scan.element.click()
        _ = try driver.waitFor(AXSelector(["id=home.rescan"]), timeout: 240)
        let clean = try driver.waitFor(AXSelector(["role=AXButton", "Clean selected"]), timeout: 20)
        try driver.requireFocus()
        clean.element.click()
        _ = try driver.waitFor(AXSelector(["role=AXButton", "Cancel"]), timeout: 20)
    }

    @MainActor
    private func openTweakDetails(_ driver: UITestDriver, probe: AXProbe? = nil) throws {
        try driver.requireFocus()
        let probe = try probe ?? AXProbe(root: scratchRoot)
        try selectSidebar("sidebar.tweaks", probe: probe, driver: driver)
        _ = try driver.waitFor(AXSelector(["id=tweaks.page"]), timeout: 60)
        let details = try driver.waitFor(
            AXSelector(["id=tweak.details.\(Self.gatedTweakID)"]), timeout: 20)
        try driver.requireFocus()
        details.element.click()
        _ = try driver.waitFor(
            AXSelector(["id=tweak.detail.\(Self.gatedTweakID)"]), timeout: 20)
    }
}

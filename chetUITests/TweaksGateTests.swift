import ChetCore
import Foundation
import XCTest

final class TweaksGateTests: UITestCase {
    private static let gatedTweakID = "appearance.autohide-menu-bar"
    private static let controlKinds = ["toggle", "choice", "range", "text", "inspect", "folder"]

    @MainActor
    func testTweaksGateDisablesEveryWriteControl() throws {
        let driver = UITestDriver(app: app)
        let probe = try AXProbe(root: scratchRoot)
        try driver.requireFocus()
        try selectSidebar("sidebar.tweaks", probe: probe, driver: driver)
        _ = try driver.waitFor(AXSelector(["id=tweaks.page"]), timeout: 60)
        let notice = try? driver.resolve(AXSelector(["value=Preview only. No tweak is changed."]))
        XCTAssertNotNil(notice)
        let statement = try? driver.resolve(
            AXSelector(["value=Preview only. Nothing is changed."]))
        XCTAssertNotNil(statement)
        for tweak in TweakCatalog.all {
            let details = try driver.waitFor(
                AXSelector(["id=tweak.details.\(tweak.id)"]), timeout: 10)
            XCTAssertEqual(details.elementTypeName, "AXButton")
            XCTAssertTrue(details.isEnabled)
            for kind in Self.controlKinds {
                guard
                    let control = try? driver.resolve(
                        AXSelector(["id=tweak.\(kind).\(tweak.id)"]))
                else { continue }
                XCTAssertFalse(
                    control.isEnabled, "tweak.\(kind).\(tweak.id) is enabled under DRY_RUN")
            }
        }
        let open = try driver.waitFor(
            AXSelector(["id=tweak.details.appearance.autohide-menu-bar"]), timeout: 10)
        try driver.requireFocus()
        open.element.click()
        _ = try driver.waitFor(
            AXSelector(["id=tweak.detail.appearance.autohide-menu-bar"]), timeout: 20)
        let reset = try driver.waitFor(AXSelector(["role=AXButton", "Reset to Default"]), timeout: 10)
        XCTAssertFalse(reset.isEnabled)
        let turnOn = try? driver.resolve(AXSelector(["role=AXButton", "Turn On"]))
        let turnOff = try? driver.resolve(AXSelector(["role=AXButton", "Turn Off"]))
        let primary = turnOn ?? turnOff
        XCTAssertNotNil(primary)
        if let primary {
            XCTAssertFalse(primary.isEnabled)
        }
    }

    @MainActor
    func testNoAutomationFilesUnderTheGate() throws {
        let driver = UITestDriver(app: app)
        try driver.requireFocus()
        try selectSidebar("sidebar.tweaks", probe: try AXProbe(root: scratchRoot), driver: driver)
        _ = try driver.waitFor(AXSelector(["id=tweaks.page"]), timeout: 60)
        try relaunch(environment: [:])
        let directory = scratchRoot.appendingPathComponent(
            "Application Support/Chet", isDirectory: true)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: directory.appendingPathComponent("tweak-automation-rules.json").path))
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: directory.appendingPathComponent("tweak-automation-state.json").path))
    }

    @MainActor
    func testConfirmSheetAppearsOnlyWithThePreviewHook() throws {
        let driver = UITestDriver(app: app)
        try driver.requireFocus()
        try selectSidebar("sidebar.tweaks", probe: try AXProbe(root: scratchRoot), driver: driver)
        _ = try driver.waitFor(AXSelector(["id=tweaks.page"]), timeout: 60)
        assertMissing(AXSelector(["id=tweak.confirm.\(Self.gatedTweakID)"]), driver)
        try relaunch(environment: ["CHET_TWEAK_PREVIEW": "confirm"])
        let probe = try AXProbe(root: scratchRoot)
        try selectSidebar("sidebar.tweaks", probe: probe, driver: driver)
        _ = try driver.waitFor(AXSelector(["id=tweaks.page"]), timeout: 60)
        _ = try driver.waitFor(
            AXSelector(["id=tweak.confirm.\(Self.gatedTweakID)"]), timeout: 60)
        let control = AXSelector(["id=tweak.toggle.\(Self.gatedTweakID)"])
        let before = try probeValue(probe, control)
        XCTAssertNotNil(before)
        let change = try? driver.resolve(
            AXSelector(["value=Change Automatically hide the menu bar?"]))
        XCTAssertNotNil(change)
        let cancel = try driver.waitFor(AXSelector(["role=AXButton", "Cancel"]), timeout: 20)
        try driver.requireFocus()
        cancel.element.click()
        XCTAssertTrue(
            waitUntilMissing(
                AXSelector(["id=tweak.confirm.\(Self.gatedTweakID)"]), driver: driver,
                timeout: 20))
        XCTAssertEqual(try probeValue(probe, control), before)
        let history = scratchRoot.appendingPathComponent("Application Support/Chet/tweaks.log")
        XCTAssertFalse(FileManager.default.fileExists(atPath: history.path))
    }
}

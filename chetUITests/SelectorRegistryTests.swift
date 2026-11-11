import AppKit
import ChetCore
import Foundation
import XCTest

final class SelectorRegistryTests: UITestCase {
    private static let documentURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("docs/ui-selectors.json")

    private static let screens = [
        "applications", "disk-map", "go", "homebrew", "mise", "overview", "settings", "tweaks",
    ]

    private struct RawDocument: Decodable {
        struct Screen: Decodable {
            struct Selector: Decodable {
                let id: String?
                let role: String?
            }
            let selectors: [Selector]
        }
        let screens: [String: Screen]
    }

    func testDocumentRegistersEachIdentifierOnce() throws {
        let document = try SelectorDocument(contentsOf: Self.documentURL)
        XCTAssertEqual(document.screenNames, Self.screens)
        XCTAssertFalse(document.generatedAt?.isEmpty ?? true)
        XCTAssertFalse(document.allIdentifiers.isEmpty)
        let data = try Data(contentsOf: Self.documentURL)
        let raw = try JSONDecoder().decode(RawDocument.self, from: data)
        var roles: [String: Set<String>] = [:]
        var all: Set<String> = []
        for screen in Self.screens {
            let identifierList = try document.identifiers(for: screen)
            XCTAssertFalse(identifierList.isEmpty, screen)
            let screenSelectors = try XCTUnwrap(raw.screens[screen], screen).selectors
            let screenIdentifiers = screenSelectors.compactMap(\.id).filter { !$0.isEmpty }
            XCTAssertEqual(
                identifierList.count, Set(screenIdentifiers).count,
                "\(screen) documents an identifier more than once")
            XCTAssertEqual(Set(identifierList), Set(screenIdentifiers), screen)
            all.formUnion(screenIdentifiers)
            for selector in screenSelectors {
                guard let identifier = selector.id, !identifier.isEmpty else { continue }
                guard let role = selector.role, !role.isEmpty else { continue }
                roles[identifier, default: []].insert(role)
            }
        }
        XCTAssertEqual(document.allIdentifiers, all.sorted())
        for (identifier, observed) in roles {
            XCTAssertEqual(
                observed.count, 1,
                "\(identifier) is documented as more than one role: \(observed.sorted())")
        }
    }

    @MainActor
    func testEveryDocumentedIdentifierResolvesOnItsScreen() throws {
        let document = try SelectorDocument(contentsOf: Self.documentURL)
        let driver = UITestDriver(app: app)
        try driver.requireFocus()
        try skipAccessGate(driver)
        let probe = try AXProbe(root: scratchRoot)
        let scan = try driver.waitFor(AXSelector(["id=home.scan"]), timeout: 20)
        try driver.requireFocus()
        scan.element.click()
        _ = try driver.waitFor(AXSelector(["id=home.empty"]), timeout: 120)
        try resolve(document, screen: "overview", driver: driver)
        let destinations = [
            ("applications", "apps.header", 120.0),
            ("disk-map", "storage.header", 60.0),
            ("go", "go.header", 120.0),
            ("homebrew", "homebrew.header", 120.0),
            ("mise", "mise.page", 60.0),
            ("tweaks", "tweaks.page", 120.0),
        ]
        for (screen, marker, timeout) in destinations {
            try selectSidebar("sidebar.\(screen)", probe: probe, driver: driver)
            _ = try driver.waitFor(AXSelector(["id=\(marker)"]), timeout: timeout)
            try resolve(document, screen: screen, driver: driver)
        }
        try selectSidebar("sidebar.overview", probe: probe, driver: driver)
        _ = try driver.waitFor(AXSelector(["id=home.header"]), timeout: 20)
        try driver.requireFocus()
        app.typeKey(",", modifierFlags: [.command])
        _ = try driver.waitFor(
            AXSelector(["id=com_apple_SwiftUI_Settings_window"]), timeout: 60)
        try resolve(document, screen: "settings", driver: driver)
    }

    @MainActor
    private func resolve(
        _ document: SelectorDocument, screen: String, driver: UITestDriver
    ) throws {
        for identifier in try document.identifiers(for: screen) {
            let element = try driver.waitFor(AXSelector(["id=\(identifier)"]), timeout: 20)
            XCTAssertFalse(element.elementTypeName.isEmpty, identifier)
        }
    }
}

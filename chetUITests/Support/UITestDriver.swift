import ChetCore
import Foundation
import XCTest

enum UITestDriverError: Error, LocalizedError, CustomStringConvertible, Equatable {
    case noMatch(selector: String, closestIdentifiers: [String])
    case multipleMatches(selector: String, matches: [String])

    var errorDescription: String? { description }

    var description: String {
        switch self {
        case .noMatch(let selector, let closestIdentifiers):
            guard !closestIdentifiers.isEmpty else {
                return "no element matches \(selector); no accessibility identifiers are available"
            }
            return "no element matches \(selector); closest identifiers: \(closestIdentifiers.joined(separator: ", "))"
        case .multipleMatches(let selector, let matches):
            return "\(matches.count) elements match \(selector): \(matches.joined(separator: ", "))"
        }
    }
}

struct UITestElement: CustomStringConvertible {
    let element: XCUIElement
    let identifier: String
    let elementTypeName: String
    let label: String
    let title: String
    let value: String
    let isEnabled: Bool

    var description: String {
        let name = identifier.isEmpty ? (label.isEmpty ? title : label) : identifier
        return "\(elementTypeName) \(name)"
    }
}

@MainActor
final class UITestDriver {
    let app: XCUIApplication

    init(app: XCUIApplication) {
        self.app = app
    }

    func requireFocus() throws {
        try FocusGuard.requireForeground(app)
    }

    func resolve(_ selector: AXSelector) throws -> UITestElement {
        if let predicate = Self.predicate(for: selector) {
            let query = app.chetWindow.descendants(matching: .any).matching(predicate)
            let count = query.count
            if count == 1 {
                return Self.project(query.firstMatch)
            }
            if count == 0 {
                throw UITestDriverError.noMatch(
                    selector: Self.describe(selector), closestIdentifiers: [])
            }
            throw UITestDriverError.multipleMatches(
                selector: Self.describe(selector),
                matches: query.allElementsBoundByIndex.map { Self.project($0).description })
        }
        let projected = projectedElements()
        let matches = projected.filter { Self.matches($0, selector) }
        switch matches.count {
        case 1:
            return matches[0]
        case 0:
            throw UITestDriverError.noMatch(
                selector: Self.describe(selector),
                closestIdentifiers: Self.closestIdentifiers(selector, in: projected))
        default:
            throw UITestDriverError.multipleMatches(
                selector: Self.describe(selector),
                matches: matches.map(\.description))
        }
    }

    func waitFor(_ selector: AXSelector, timeout: TimeInterval = 5) throws -> UITestElement {
        let deadline = Date().addingTimeInterval(timeout)
        if let predicate = Self.predicate(for: selector) {
            let query = app.chetWindow.descendants(matching: .any).matching(predicate)
            if query.firstMatch.waitForExistence(timeout: timeout) {
                if query.count == 1 {
                    return Self.project(query.firstMatch)
                }
                throw UITestDriverError.multipleMatches(
                    selector: Self.describe(selector),
                    matches: query.allElementsBoundByIndex.map { Self.project($0).description })
            }
        }
        while Date() < deadline {
            let projected = projectedElements()
            let matches = projected.filter { Self.matches($0, selector) }
            if matches.count == 1 {
                return matches[0]
            }
            if matches.count > 1 {
                throw UITestDriverError.multipleMatches(
                    selector: Self.describe(selector),
                    matches: matches.map(\.description))
            }
            let remaining = max(0, deadline.timeIntervalSinceNow)
            RunLoop.current.run(until: Date().addingTimeInterval(min(0.5, remaining)))
        }
        let projected = projectedElements()
        let matches = projected.filter { Self.matches($0, selector) }
        if matches.count > 1 {
            throw UITestDriverError.multipleMatches(
                selector: Self.describe(selector),
                matches: matches.map(\.description))
        }
        throw UITestDriverError.noMatch(
            selector: Self.describe(selector),
            closestIdentifiers: Self.closestIdentifiers(selector, in: projected))
    }

    private func projectedElements() -> [UITestElement] {
        app.chetWindow.descendants(matching: .any).allElementsBoundByIndex.map(Self.project)
    }

    static func predicate(for selector: AXSelector) -> NSPredicate? {
        var parts: [NSPredicate] = []
        for term in selector.terms {
            switch term.key {
            case .id?:
                parts.append(NSPredicate(format: "identifier == %@", term.value))
            case .desc?, .description?:
                parts.append(NSPredicate(format: "label == %@", term.value))
            case .title?:
                parts.append(NSPredicate(format: "title == %@", term.value))
            case .value?:
                parts.append(NSPredicate(format: "value == %@", term.value))
            case .enabled?:
                guard let expected = flag(term.value) else { return nil }
                parts.append(NSPredicate(format: "enabled == %@", NSNumber(value: expected)))
            case .contains?:
                parts.append(
                    NSPredicate(
                        format:
                            "identifier CONTAINS[c] %@ OR label CONTAINS[c] %@ OR title CONTAINS[c] %@ OR value CONTAINS[c] %@",
                        term.value, term.value, term.value, term.value))
            case .role?:
                let types = elementTypes(named: term.value)
                guard !types.isEmpty else { return nil }
                if types.count == 1 {
                    parts.append(NSPredicate(format: "elementType == %d", types[0].rawValue))
                } else {
                    parts.append(
                        NSCompoundPredicate(
                            orPredicateWithSubpredicates: types.map {
                                NSPredicate(format: "elementType == %d", $0.rawValue)
                            }))
                }
            case nil:
                return nil
            }
        }
        guard !parts.isEmpty else { return nil }
        return NSCompoundPredicate(andPredicateWithSubpredicates: parts)
    }

    private static func elementTypes(named role: String) -> [XCUIElement.ElementType] {
        roleNames.filter { $0.value == role }.map(\.key)
    }

    private static func flag(_ raw: String) -> Bool? {
        switch raw.lowercased() {
        case "true", "1": return true
        case "false", "0": return false
        default: return nil
        }
    }

    private static func project(_ element: XCUIElement) -> UITestElement {
        UITestElement(
            element: element,
            identifier: element.identifier,
            elementTypeName: typeName(element.elementType),
            label: element.label,
            title: element.title,
            value: valueString(element.value),
            isEnabled: element.isEnabled)
    }

    private static func matches(_ element: UITestElement, _ selector: AXSelector) -> Bool {
        selector.matches(
            id: element.identifier,
            role: element.elementTypeName,
            desc: element.label,
            title: element.title,
            value: element.value,
            enabled: element.isEnabled)
    }

    private static let roleNames: [XCUIElement.ElementType: String] = [
        .any: "AXAny",
        .other: "AXUnknown",
        .application: "AXApplication",
        .group: "AXGroup",
        .window: "AXWindow",
        .sheet: "AXSheet",
        .drawer: "AXDrawer",
        .alert: "AXAlert",
        .dialog: "AXDialog",
        .button: "AXButton",
        .radioButton: "AXRadioButton",
        .radioGroup: "AXRadioGroup",
        .checkBox: "AXCheckBox",
        .disclosureTriangle: "AXDisclosureTriangle",
        .popUpButton: "AXPopUpButton",
        .comboBox: "AXComboBox",
        .menuButton: "AXMenuButton",
        .toolbarButton: "AXButton",
        .popover: "AXPopover",
        .keyboard: "AXKeyboard",
        .key: "AXKey",
        .navigationBar: "AXNavigationBar",
        .tabBar: "AXTabBar",
        .tabGroup: "AXTabGroup",
        .toolbar: "AXToolbar",
        .statusBar: "AXStatusBar",
        .table: "AXTable",
        .tableRow: "AXRow",
        .tableColumn: "AXColumn",
        .outline: "AXOutline",
        .outlineRow: "AXRow",
        .browser: "AXBrowser",
        .collectionView: "AXCollectionView",
        .slider: "AXSlider",
        .pageIndicator: "AXPageIndicator",
        .progressIndicator: "AXProgressIndicator",
        .activityIndicator: "AXActivityIndicator",
        .segmentedControl: "AXSegmentedControl",
        .picker: "AXPicker",
        .pickerWheel: "AXPickerWheel",
        .switch: "AXCheckBox",
        .toggle: "AXCheckBox",
        .link: "AXLink",
        .image: "AXImage",
        .icon: "AXImage",
        .searchField: "AXSearchField",
        .scrollView: "AXScrollArea",
        .scrollBar: "AXScrollBar",
        .staticText: "AXStaticText",
        .textField: "AXTextField",
        .secureTextField: "AXTextField",
        .datePicker: "AXDateField",
        .textView: "AXTextArea",
        .menu: "AXMenu",
        .menuItem: "AXMenuItem",
        .menuBar: "AXMenuBar",
        .menuBarItem: "AXMenuBarItem",
        .map: "AXMap",
        .webView: "AXWebArea",
        .incrementArrow: "AXButton",
        .decrementArrow: "AXButton",
        .timeline: "AXTimeline",
        .ratingIndicator: "AXRatingIndicator",
        .valueIndicator: "AXValueIndicator",
        .splitGroup: "AXSplitGroup",
        .splitter: "AXSplitter",
        .relevanceIndicator: "AXRelevanceIndicator",
        .colorWell: "AXColorWell",
        .helpTag: "AXHelpTag",
        .matte: "AXMatte",
        .dockItem: "AXDockItem",
        .ruler: "AXRuler",
        .rulerMarker: "AXRulerMarker",
        .grid: "AXGrid",
        .levelIndicator: "AXLevelIndicator",
        .cell: "AXCell",
        .layoutArea: "AXLayoutArea",
        .layoutItem: "AXLayoutItem",
        .handle: "AXHandle",
        .stepper: "AXStepper",
        .tab: "AXTab",
        .touchBar: "AXTouchBar",
        .statusItem: "AXStatusItem",
    ]

    private static func typeName(_ type: XCUIElement.ElementType) -> String {
        roleNames[type] ?? "AXUnknown"
    }

    private static func valueString(_ value: Any?) -> String {
        guard let value else { return "" }
        if let text = value as? String {
            return text
        }
        if let number = value as? NSNumber {
            return number.stringValue
        }
        return String(describing: value)
    }

    private static func describe(_ selector: AXSelector) -> String {
        let terms = selector.terms.map { term -> String in
            guard let key = term.key, key != .contains else { return term.value }
            if key == .description { return "desc=\(term.value)" }
            return "\(key.rawValue)=\(term.value)"
        }
        return terms.isEmpty ? "<empty selector>" : terms.joined(separator: " ")
    }

    private static func closestIdentifiers(
        _ selector: AXSelector, in elements: [UITestElement], limit: Int = 5
    ) -> [String] {
        let terms = selector.terms.map(\.value).filter { !$0.isEmpty }
        var distances: [String: Int] = [:]
        for element in elements where !element.identifier.isEmpty {
            let fields = [element.identifier, element.label, element.title, element.value]
                .filter { !$0.isEmpty }
            var distance = Int.max
            if terms.isEmpty {
                distance = 0
            } else {
                for term in terms {
                    for field in fields {
                        distance = min(distance, similarity(term, field))
                    }
                }
            }
            if let known = distances[element.identifier] {
                distances[element.identifier] = min(known, distance)
            } else {
                distances[element.identifier] = distance
            }
        }
        let ordered = distances.sorted { left, right in
            if left.value != right.value { return left.value < right.value }
            return left.key < right.key
        }
        return ordered.prefix(limit).map(\.key)
    }

    private static func similarity(_ left: String, _ right: String) -> Int {
        let a = left.lowercased()
        let b = right.lowercased()
        if a == b { return 0 }
        if a.contains(b) || b.contains(a) { return 1 }
        return editDistance(a, b)
    }

    private static func editDistance(_ left: String, _ right: String) -> Int {
        let a = Array(left)
        let b = Array(right)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var previous = Array(0...b.count)
        var current = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            current[0] = i
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
            }
            swap(&previous, &current)
        }
        return previous[b.count]
    }
}

extension XCUIApplication {
    var chetWindow: XCUIElement { windows.element(boundBy: 0) }
}

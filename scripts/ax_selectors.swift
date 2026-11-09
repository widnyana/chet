import AppKit
import ApplicationServices
import Foundation

/// Dumps the accessibility tree of one running app window as JSON on stdout.
/// Used by `scripts/ui_selectors.py`; the Python wrapper owns pid lookup, merging,
/// and the output file.

func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success
        ? value : nil
}

func string(_ element: AXUIElement, _ name: String) -> String {
    (attribute(element, name) as? String) ?? ""
}

func actions(_ element: AXUIElement) -> [String] {
    var names: CFArray?
    AXUIElementCopyActionNames(element, &names)
    return (names as? [String]) ?? []
}

func point(_ element: AXUIElement, _ name: String) -> CGPoint? {
    guard let raw = attribute(element, name) else { return nil }
    var point = CGPoint.zero
    AXValueGetValue(raw as! AXValue, .cgPoint, &point)
    return point
}

func size(_ element: AXUIElement, _ name: String) -> CGSize? {
    guard let raw = attribute(element, name) else { return nil }
    var size = CGSize.zero
    AXValueGetValue(raw as! AXValue, .cgSize, &size)
    return size
}

let actionableRoles: Set<String> = [
    "AXButton", "AXCheckBox", "AXRadioButton", "AXPopUpButton", "AXSlider", "AXTextField",
    "AXLink", "AXRow", "AXOutline", "AXSheet", "AXWindow", "AXMenuButton", "AXDisclosureTriangle",
    "AXRadioGroup", "AXTabGroup",
]

func walk(_ element: AXUIElement, _ path: [String], _ depth: Int, _ nodes: inout [[String: Any]]) {
    if depth > 60 { return }
    let role = string(element, "AXRole")
    let identifier = string(element, "AXIdentifier")
    let description = string(element, "AXDescription")
    let title = string(element, "AXTitle")
    let value = string(element, "AXValue")

    // Inventory rows carry one description per installed app. They differ on every Mac and
    // would make the saved selector list drift, so they are skipped.
    let perAppLabel = description.hasPrefix("Show files left by ") || description.hasPrefix("Select ")
    let interesting =
        !identifier.isEmpty
        || actionableRoles.contains(role)
        || (!description.isEmpty && role != "AXStaticText")
        || (!title.isEmpty && role != "AXStaticText")

    if interesting, !perAppLabel {
        var entry: [String: Any] = [
            "role": role,
            "path": path,
            "enabled": (attribute(element, "AXEnabled") as? Bool) ?? false,
            "actions": actions(element),
        ]
        if !identifier.isEmpty, !identifier.hasPrefix("SwiftUI.") { entry["id"] = identifier }
        if !description.isEmpty { entry["description"] = description }
        if !title.isEmpty { entry["title"] = title }
        if !value.isEmpty { entry["value"] = value }
        if let position = point(element, "AXPosition") {
            entry["x"] = Int(position.x)
            entry["y"] = Int(position.y)
        }
        if let size = size(element, "AXSize") {
            entry["width"] = Int(size.width)
            entry["height"] = Int(size.height)
        }
        nodes.append(entry)
    }

    let childPath = path + [role]
    if let children = attribute(element, kAXChildrenAttribute as String) as? [AXUIElement] {
        for child in children { walk(child, childPath, depth + 1, &nodes) }
    }
}

guard CommandLine.arguments.count > 1, let pid = Int32(CommandLine.arguments[1]) else {
    FileHandle.standardError.write(Data("usage: ax_selectors <pid>\n".utf8))
    exit(2)
}

let app = AXUIElementCreateApplication(pid)
var windows: [[String: Any]] = []
var nodes: [[String: Any]] = []
let windowElements = (attribute(app, kAXWindowsAttribute as String) as? [AXUIElement]) ?? []
for window in windowElements {
    walk(window, [], 0, &nodes)
    windows.append([
        "title": string(window, "AXTitle"),
        "role": string(window, "AXRole"),
    ])
}

let output: [String: Any] = [
    "pid": Int(pid),
    "windows": windows,
    "nodes": nodes,
]
let data = try JSONSerialization.data(withJSONObject: output, options: [.sortedKeys])
FileHandle.standardOutput.write(data)

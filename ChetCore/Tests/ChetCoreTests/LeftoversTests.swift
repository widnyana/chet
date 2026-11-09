import Foundation
import Testing

@testable import ChetCore

struct LeftoversTests {
    @Test func flagsOnlyOrphanedBundleIDs() throws {
        let dir = try TempDir()
        try dir.file("Library/Preferences/com.gone.app.plist", bytes: 100)
        try dir.file("Library/Preferences/com.apple.finder.plist", bytes: 100)
        try dir.file("Library/Preferences/com.installed.app.plist", bytes: 100)
        try dir.file("Library/Preferences/com.installed.helper.plist", bytes: 100)
        try dir.file("Library/Application Support/Google/x", bytes: 100)
        try dir.file("Library/Application Support/Steam/x", bytes: 100)
        try dir.file("Library/Containers/com.gone.other/x", bytes: 100)
        let scanner = LeftoverScanner(home: dir.url, installedBundleIDs: ["com.installed.app"])
        let names = Set(try scanner.scan().map(\.url.lastPathComponent))
        #expect(names == ["com.gone.app.plist", "com.gone.other"])
    }

    @Test(arguments: [
        ("com.foo.app.plist", "com.foo.app"),
        ("group.com.foo.shared", "com.foo.shared"),
        ("ABCDE12345.com.foo.shared", "com.foo.shared"),
        ("com.foo.app.savedState", "com.foo.app"),
    ])
    func parsesBundleIDs(name: String, expected: String) {
        #expect(LeftoverScanner.bundleID(fromName: name) == expected)
    }

    @Test(arguments: ["Google", "Steam", ".GlobalPreferences.plist", "com.foo", "a..b.c"])
    func rejectsNonBundleNames(name: String) {
        #expect(LeftoverScanner.bundleID(fromName: name) == nil)
    }

    @Test func readsInstalledBundleIDs() throws {
        let dir = try TempDir()
        let plist = dir.url.appendingPathComponent("Foo.app/Contents/Info.plist")
        try FileManager.default.createDirectory(
            at: plist.deletingLastPathComponent(), withIntermediateDirectories: true)
        let info: NSDictionary = ["CFBundleIdentifier": "com.test.foo", "CFBundlePackageType": "APPL"]
        try info.write(to: plist)
        #expect(LeftoverScanner.installedBundleIDs(in: [dir.url]).contains("com.test.foo"))
    }
}

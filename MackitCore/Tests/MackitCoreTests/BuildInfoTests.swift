import Foundation
import Testing

@testable import MackitCore

@Suite("BuildInfo")
struct BuildInfoTests {
    @Test func fieldsComeFromTheBundle() throws {
        let dir = try TempDir()
        try dir.text(
            "Info.plist",
            plist(version: "9.9.9", build: "42", bundleID: "test.example", minimumOS: "26.0"))
        let bundle = try #require(Bundle(url: dir.url))
        let info = BuildInfo.current(bundle: bundle)
        #expect(info.version == "9.9.9")
        #expect(info.build == "42")
        #expect(info.bundleID == "test.example")
        #expect(info.minimumOS == "26.0")
        #expect(info.architecture == "arm64")
    }

    @Test func missingFieldsStayNil() throws {
        let dir = try TempDir()
        try dir.text("Info.plist", plist(version: nil, build: nil, bundleID: nil, minimumOS: nil))
        let bundle = try #require(Bundle(url: dir.url))
        let info = BuildInfo.current(bundle: bundle)
        #expect(info.version == nil)
        #expect(info.build == nil)
        #expect(info.bundleID == nil)
        #expect(info.minimumOS == nil)
    }

    @Test func unexpandedMinimumOSIsNotAVersion() throws {
        let dir = try TempDir()
        try dir.text(
            "Info.plist",
            plist(
                version: "1.0", build: "1", bundleID: "test.example",
                minimumOS: "$(MACOSX_DEPLOYMENT_TARGET)"))
        let bundle = try #require(Bundle(url: dir.url))
        let info = BuildInfo.current(bundle: bundle)
        #expect(info.minimumOS == nil)
    }

    private func plist(version: String?, build: String?, bundleID: String?, minimumOS: String?) -> String {
        var entries = ""
        func add(_ key: String, _ value: String?) {
            guard let value else { return }
            entries += "<key>\(key)</key><string>\(value)</string>"
        }
        add("CFBundleShortVersionString", version)
        add("CFBundleVersion", build)
        add("CFBundleIdentifier", bundleID)
        add("LSMinimumSystemVersion", minimumOS)
        return """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0"><dict>\(entries)</dict></plist>
            """
    }
}

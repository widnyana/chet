import Foundation
import Testing

@testable import ChetCore

@Suite("BuildInfo")
struct BuildInfoTests {
    @Test func fieldsComeFromTheBundle() throws {
        let dir = try TempDir()
        try dir.text("Info.plist", plist(version: "9.9.9", build: "42", minimumOS: "26.0"))
        let bundle = try #require(Bundle(url: dir.url))
        let info = BuildInfo.current(bundle: bundle)
        #expect(info.version == "9.9.9")
        #expect(info.build == "42")
        #expect(info.minimumOS == "26.0")
    }

    @Test func missingFieldsStayNil() throws {
        let dir = try TempDir()
        try dir.text("Info.plist", plist(version: nil, build: nil, minimumOS: nil))
        let bundle = try #require(Bundle(url: dir.url))
        let info = BuildInfo.current(bundle: bundle)
        #expect(info.version == nil)
        #expect(info.build == nil)
        #expect(info.minimumOS == nil)
    }

    @Test func unexpandedMinimumOSIsNotAVersion() throws {
        let dir = try TempDir()
        try dir.text(
            "Info.plist",
            plist(version: "1.0", build: "1", minimumOS: "$(MACOSX_DEPLOYMENT_TARGET)"))
        let bundle = try #require(Bundle(url: dir.url))
        let info = BuildInfo.current(bundle: bundle)
        #expect(info.minimumOS == nil)
    }

    @Test func commitAndBuildDateComeFromTheBundle() throws {
        let dir = try TempDir()
        try dir.text(
            "Info.plist",
            plist(
                version: "1.0", build: "1", minimumOS: "26.0",
                commit: "abc1234def5678", builtAt: "2026-11-11T09:30:00Z"))
        let bundle = try #require(Bundle(url: dir.url))
        let info = BuildInfo.current(bundle: bundle)
        #expect(info.commit == "abc1234def5678")
        #expect(info.shortCommit == "abc1234")
        #expect(info.builtAt == "2026-11-11T09:30:00Z")
        #expect(info.builtDate?.formatted(.iso8601) == "2026-11-11T09:30:00Z")
    }

    @Test func commitAndBuildDateStayNilWhenAbsent() throws {
        let dir = try TempDir()
        try dir.text("Info.plist", plist(version: "1.0", build: "1", minimumOS: "26.0"))
        let bundle = try #require(Bundle(url: dir.url))
        let info = BuildInfo.current(bundle: bundle)
        #expect(info.commit == nil)
        #expect(info.shortCommit == nil)
        #expect(info.builtAt == nil)
        #expect(info.builtDate == nil)
    }

    @Test func unexpandedBuildSettingsAreUnknown() throws {
        let dir = try TempDir()
        try dir.text(
            "Info.plist",
            plist(
                version: "1.0", build: "1", minimumOS: "26.0",
                commit: "$(CHET_GIT_COMMIT)", builtAt: "$(CHET_BUILD_DATE)"))
        let bundle = try #require(Bundle(url: dir.url))
        let info = BuildInfo.current(bundle: bundle)
        #expect(info.commit == nil)
        #expect(info.builtAt == nil)
        #expect(info.builtDate == nil)
    }

    @Test func emptyValuesAreUnknown() throws {
        let dir = try TempDir()
        try dir.text(
            "Info.plist",
            plist(
                version: "1.0", build: "1", minimumOS: "26.0",
                commit: "", builtAt: ""))
        let bundle = try #require(Bundle(url: dir.url))
        let info = BuildInfo.current(bundle: bundle)
        #expect(info.commit == nil)
        #expect(info.builtAt == nil)
        #expect(info.builtDate == nil)
    }

    @Test func unparseableBuildDateStaysVerbatim() throws {
        let dir = try TempDir()
        try dir.text(
            "Info.plist",
            plist(
                version: "1.0", build: "1", minimumOS: "26.0",
                commit: "abc1234", builtAt: "not a date"))
        let bundle = try #require(Bundle(url: dir.url))
        let info = BuildInfo.current(bundle: bundle)
        #expect(info.builtAt == "not a date")
        #expect(info.builtDate == nil)
    }

    private func plist(
        version: String?, build: String?, minimumOS: String?,
        commit: String? = nil, builtAt: String? = nil
    ) -> String {
        var entries = ""
        func add(_ key: String, _ value: String?) {
            guard let value else { return }
            entries += "<key>\(key)</key><string>\(value)</string>"
        }
        add("CFBundleShortVersionString", version)
        add("CFBundleVersion", build)
        add("LSMinimumSystemVersion", minimumOS)
        add("ChetGitCommit", commit)
        add("ChetBuildDate", builtAt)
        return """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0"><dict>\(entries)</dict></plist>
            """
    }
}

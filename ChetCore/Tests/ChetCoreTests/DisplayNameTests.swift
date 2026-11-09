import Foundation
import Testing

@testable import ChetCore

struct DisplayNameTests {
    let home = URL(fileURLWithPath: "/Users/test")

    private func url(_ relative: String) -> URL { home.appendingPathComponent(relative) }

    @Test func firefoxProfileDropsRandomPrefix() {
        #expect(
            DisplayName.title(for: url("Library/Caches/Firefox/Profiles/4j2keovq.default-release"), home: home)
                == "default-release")
    }

    @Test func chromeProfileKeepsItsName() {
        #expect(DisplayName.title(for: url("Library/Caches/Google/Chrome/Profile 4"), home: home) == "Profile 4")
    }

    @Test func knownToolCacheGetsFriendlyName() {
        #expect(DisplayName.title(for: url("Library/Caches/go-build"), home: home) == "Go build cache")
        #expect(DisplayName.title(for: url(".npm/_cacache"), home: home) == "npm")
    }

    @Test func locationUsesTilde() {
        #expect(
            DisplayName.location(of: url("Library/Caches/Google/Chrome/Profile 4"), home: home)
                == "~/Library/Caches/Google/Chrome")
        #expect(DisplayName.location(of: url("file.txt"), home: home) == "~")
        #expect(DisplayName.location(of: URL(fileURLWithPath: "/Volumes/X/a/b"), home: home) == "/Volumes/X/a")
    }

    @Test func sourcePrefersOwnerThenBundleIDFolder() {
        let profile = url("Library/Caches/Google/Chrome/Profile 4")
        #expect(DisplayName.sourceBundleID(for: profile, owner: "com.google.Chrome") == "com.google.Chrome")
        #expect(
            DisplayName.sourceBundleID(for: url("Library/Caches/com.spotify.client"), owner: nil)
                == "com.spotify.client")
        #expect(DisplayName.sourceBundleID(for: url("Library/Caches/foo"), owner: nil) == nil)
    }

    @Test func bundleIDPartsSplitsReverseDNS() throws {
        #expect(try #require(DisplayName.bundleIDParts("com.apple.HomeKit")) == (title: "HomeKit", vendor: "apple"))
        #expect(try #require(DisplayName.bundleIDParts("com.example.tool")) == (title: "tool", vendor: "example"))
        #expect(
            try #require(DisplayName.bundleIDParts("com.apple.managedappdistributionagent"))
                == (title: "managedappdistributionagent", vendor: "apple"))
        #expect(DisplayName.bundleIDParts("HomeKit") == nil)
    }
}

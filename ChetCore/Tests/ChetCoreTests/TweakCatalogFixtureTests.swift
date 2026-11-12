import Foundation
import Testing

@testable import ChetCore

struct TweakCatalogFixtureTests {
    private struct Fixture {
        let target: String
        let defaultValue: TweakValue?
        let options: [TweakOption]
    }

    private static let home = FileManager.default.homeDirectoryForCurrentUser.path

    private static func row(
        _ target: String, _ defaultValue: TweakValue? = nil, _ options: [TweakOption] = []
    ) -> Fixture {
        Fixture(target: target, defaultValue: defaultValue, options: options)
    }

    private static func option(_ label: String, _ value: TweakValue) -> TweakOption {
        TweakOption(label: label, value: value)
    }

    private static let table: [String: Fixture] = [
        "finder.hidden-files": row("defaults:com.apple.finder:AppleShowAllFiles"),
        "finder.extensions": row("defaults:NSGlobalDomain:AppleShowAllExtensions"),
        "finder.path-bar": row("defaults:com.apple.finder:ShowPathbar"),
        "finder.status-bar": row("defaults:com.apple.finder:ShowStatusBar"),
        "finder.folders-first": row("defaults:com.apple.finder:_FXSortFoldersFirst", .boolean(true)),
        "finder.search-current": row(
            "defaults:com.apple.finder:FXDefaultSearchScope", .string("SCev"),
            [
                option("Current folder", .string("SCcf")),
                option("This Mac", .string("SCev")),
                option("Previous scope", .string("SCsp")),
            ]),
        "finder.quit": row("defaults:com.apple.finder:QuitMenuItem"),
        "finder.user-library": row("file:\(home)/Library", .boolean(false)),
        "finder.extension-warning": row(
            "defaults:com.apple.finder:FXEnableExtensionChangeWarning", .boolean(true)),
        "finder.ds-store-network": row(
            "defaults:com.apple.desktopservices:DSDontWriteNetworkStores", .boolean(false)),
        "finder.default-view": row(
            "defaults:com.apple.finder:FXPreferredViewStyle", .string("icnv"),
            [
                option("Icon", .string("icnv")),
                option("List", .string("Nlsv")),
                option("Column", .string("clmv")),
                option("Gallery", .string("glyv")),
            ]),
        "dock.autohide": row("defaults:com.apple.dock:autohide"),
        "dock.magnification": row("defaults:com.apple.dock:magnification"),
        "dock.minimize-to-app": row("defaults:com.apple.dock:minimize-to-application"),
        "dock.recent-apps": row("defaults:com.apple.dock:show-recents", .boolean(true)),
        "dock.mineffect": row(
            "defaults:com.apple.dock:mineffect", .string("genie"),
            [option("Genie", .string("genie")), option("Scale", .string("scale"))]),
        "dock.autohide-speed": row("defaults:com.apple.dock:autohide-time-modifier", .number(0.5)),
        "dock.reveal-delay": row("defaults:com.apple.dock:autohide-delay", .number(0.2)),
        "dock.mru-spaces": row("defaults:com.apple.dock:mru-spaces"),
        "dock.orientation": row(
            "defaults:com.apple.dock:orientation", .string("bottom"),
            [
                option("Left", .string("left")),
                option("Bottom", .string("bottom")),
                option("Right", .string("right")),
            ]),
        "dock.tilesize": row("defaults:com.apple.dock:tilesize", .integer(64)),
        "dock.expose-group-apps": row("defaults:com.apple.dock:expose-group-apps"),
        "global.natural-scrolling": row(
            "defaults:NSGlobalDomain:com.apple.swipescrolldirection", .boolean(true)),
        "appearance.clock-format": row("defaults:com.apple.menuextra.clock:DateFormat"),
        "finder.posix-path": row("defaults:com.apple.finder:_FXShowPosixPathInTitle"),
        "keyboard.repeat": row("defaults:NSGlobalDomain:ApplePressAndHoldEnabled", .boolean(true)),
        "keyboard.full-access": row("defaults:NSGlobalDomain:AppleKeyboardUIMode", .integer(0)),
        "keyboard.smart-quotes": row(
            "defaults:NSGlobalDomain:NSAutomaticQuoteSubstitutionEnabled", .boolean(true)),
        "keyboard.smart-dashes": row(
            "defaults:NSGlobalDomain:NSAutomaticDashSubstitutionEnabled", .boolean(false)),
        "keyboard.autocorrect": row(
            "defaults:NSGlobalDomain:NSAutomaticSpellingCorrectionEnabled", .boolean(true)),
        "keyboard.auto-capitalization": row(
            "defaults:NSGlobalDomain:NSAutomaticCapitalizationEnabled", .boolean(true)),
        "keyboard.double-space-period": row(
            "defaults:NSGlobalDomain:NSAutomaticPeriodSubstitutionEnabled", .boolean(true)),
        "keyboard.text-completion": row(
            "defaults:NSGlobalDomain:NSAutomaticTextCompletionEnabled", .boolean(false)),
        "keyboard.repeat-rate": row("defaults:NSGlobalDomain:KeyRepeat", .integer(6)),
        "keyboard.initial-delay": row("defaults:NSGlobalDomain:InitialKeyRepeat", .integer(25)),
        "trackpad.tap-to-click": row(
            "defaults:com.apple.AppleMultitouchTrackpad:Clicking", .boolean(false)),
        "trackpad.three-finger-drag": row(
            "defaults:com.apple.AppleMultitouchTrackpad:TrackpadThreeFingerDrag", .boolean(false)),
        "screenshots.format": row(
            "defaults:com.apple.screencapture:type", .string("png"),
            [
                option("PNG", .string("png")),
                option("JPEG", .string("jpg")),
                option("TIFF", .string("tiff")),
                option("PDF", .string("pdf")),
            ]),
        "screenshots.location": row(
            "defaults:com.apple.screencapture:location", .string("~/Desktop")),
        "screenshots.shadow": row("defaults:com.apple.screencapture:disable-shadow", .boolean(false)),
        "screenshots.thumbnail": row("defaults:com.apple.screencapture:show-thumbnail", .boolean(true)),
        "screenshots.filename": row("defaults:com.apple.screencapture:name", .string("Screenshot")),
        "appearance.dark": row("defaults:NSGlobalDomain:AppleInterfaceStyle"),
        "appearance.reduce-motion": row("defaults:com.apple.universalaccess:reduceMotion"),
        "appearance.reduce-transparency": row("defaults:com.apple.universalaccess:reduceTransparency"),
        "appearance.increase-contrast": row("defaults:com.apple.universalaccess:increaseContrast"),
        "appearance.menu-bar-seconds": row("defaults:com.apple.menuextra.clock:ShowSeconds"),
        "appearance.autohide-menu-bar": row("defaults:NSGlobalDomain:_HIHideMenuBar"),
        "windows.reduce-animations": row(
            "defaults:NSGlobalDomain:NSAutomaticWindowAnimationsEnabled", .boolean(true)),
        "windows.double-click": row(
            "defaults:NSGlobalDomain:AppleActionOnDoubleClick", .string("Maximize"),
            [
                option("Zoom", .string("Maximize")),
                option("Minimize", .string("Minimize")),
                option("Do nothing", .string("None")),
            ]),
        "windows.document-tabs": row(
            "defaults:NSGlobalDomain:AppleWindowTabbingMode", .string("automatic"),
            [
                option("Automatic", .string("automatic")),
                option("Always", .string("always")),
                option("Manually", .string("manual")),
            ]),
        "windows.restore-state": row(
            "defaults:NSGlobalDomain:NSQuitAlwaysKeepsWindows", .boolean(true)),
        "windows.stage-manager": row(
            "defaults:com.apple.WindowManager:GloballyEnabled", .boolean(false)),
        "security.firewall": row("probe:firewall"),
        "security.filevault": row("probe:fileVault"),
        "security.gatekeeper": row("probe:gatekeeper"),
        "security.automatic-updates": row("probe:automaticUpdates"),
        "developer.xcode-tools": row("probe:xcodeTools"),
        "developer.login-shell": row("probe:loginShell"),
        "developer.homebrew": row("probe:homebrew"),
        "developer.virtualization": row("probe:virtualization"),
    ]

    private func targetLabel(_ target: TweakTarget) -> String {
        switch target {
        case .defaults(let domain, let key, _): "defaults:\(domain):\(key)"
        case .fileHidden(let path): "file:\(path)"
        case .probe(let probe): "probe:\(probe.rawValue)"
        }
    }

    @Test func everyCatalogRowHasAFixtureEntry() {
        #expect(Set(Self.table.keys) == Set(TweakCatalog.all.map(\.id)))
    }

    @Test func everyFixtureEntryMatchesTheCatalog() throws {
        for tweak in TweakCatalog.all {
            let fixture = try #require(Self.table[tweak.id], "missing fixture for \(tweak.id)")
            #expect(targetLabel(tweak.target) == fixture.target, "target mismatch for \(tweak.id)")
            #expect(tweak.defaultValue == fixture.defaultValue, "default mismatch for \(tweak.id)")
            let options: [TweakOption]
            if case .choice(let list) = tweak.control { options = list } else { options = [] }
            #expect(options == fixture.options, "options mismatch for \(tweak.id)")
        }
    }
}

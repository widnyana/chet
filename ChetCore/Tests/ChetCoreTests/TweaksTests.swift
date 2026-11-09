import Foundation
import Testing

@testable import ChetCore

struct TweaksTests {
    // MARK: Parsing

    @Test func parsesEachDeclaredType() {
        #expect(TweakEngine.parse("1\n", type: .boolean) == .boolean(true))
        #expect(TweakEngine.parse("0", type: .boolean) == .boolean(false))
        #expect(TweakEngine.parse("true", type: .boolean) == .boolean(true))
        #expect(TweakEngine.parse("maybe", type: .boolean) == nil)
        #expect(TweakEngine.parse("2", type: .integer) == .integer(2))
        #expect(TweakEngine.parse("0.5", type: .number) == .number(0.5))
        #expect(TweakEngine.parse("Dark", type: .string) == .string("Dark"))
        #expect(TweakEngine.parse("", type: .string) == .string(""))
    }

    @Test func recognizesMissingKeyMessages() {
        #expect(
            TweakEngine.isMissing(
                "Error: Could not find key 'ShowSeconds' in domain 'com.apple.menuextra.clock'."))
        #expect(TweakEngine.isMissing("Domain com.example.does not exist"))
        #expect(!TweakEngine.isMissing("The operation could not be completed."))
    }

    // MARK: State

    @Test func toggleStateReadsOnOffAndCustom() throws {
        let tweak = toggleTweak(domain: domain())
        #expect(TweakEngine.state(for: tweak, current: .boolean(true)) == .on)
        #expect(TweakEngine.state(for: tweak, current: .boolean(false)) == .off)
        #expect(TweakEngine.state(for: tweak, current: .string("weird")) == .custom("weird"))
    }

    @Test func absentKeyFallsBackToTheDeclaredDefault() {
        let onByDefault = Tweak(
            id: "test.on-default", category: .keyboard, name: "Name", summary: "Summary",
            detail: "Detail", impact: "Impact",
            target: .defaults(domain: "com.chet.tweaks.tests", key: "probe", type: .boolean),
            control: .toggle(on: .boolean(true), off: .boolean(false)),
            defaultValue: .boolean(true))
        #expect(TweakEngine.state(for: onByDefault, current: nil) == .on)
        #expect(!TweakReading(tweak: onByDefault, state: .on, current: nil).isCustomized)

        let absentIsOff = Tweak(
            id: "test.absent-off", category: .appearance, name: "Name", summary: "Summary",
            detail: "Detail", impact: "Impact",
            target: .defaults(domain: "com.chet.tweaks.tests", key: "probe", type: .string),
            control: .toggle(on: .string("Dark"), off: nil))
        #expect(TweakEngine.state(for: absentIsOff, current: nil) == .off)
    }

    @Test func customizedMeansWrittenAndDifferentFromDefault() {
        let tweak = toggleTweak(domain: domain())
        #expect(!TweakReading(tweak: tweak, state: .off, current: nil).isCustomized)
        #expect(!TweakReading(tweak: tweak, state: .off, current: .boolean(false)).isCustomized)
        #expect(TweakReading(tweak: tweak, state: .on, current: .boolean(true)).isCustomized)
    }

    @Test func choiceStateUsesOptionLabels() {
        let tweak = Tweak(
            id: "test.choice", category: .screenshots, name: "Format", summary: "Summary",
            detail: "Detail", impact: "Impact",
            target: .defaults(domain: "com.chet.tweaks.tests", key: "t", type: .string),
            control: .choice([
                TweakOption(label: "PNG", value: .string("png")),
                TweakOption(label: "JPEG", value: .string("jpg")),
            ]),
            defaultValue: .string("png"))
        #expect(TweakEngine.state(for: tweak, current: nil) == .value("PNG"))
        #expect(TweakEngine.state(for: tweak, current: .string("jpg")) == .value("JPEG"))
        #expect(TweakEngine.state(for: tweak, current: .string("gif")) == .custom("gif"))
    }

    @Test func folderStateShortensTheHomePrefix() {
        let tweak = Tweak(
            id: "test.folder", category: .screenshots, name: "Folder", summary: "Summary",
            detail: "Detail", impact: "Impact",
            target: .defaults(domain: "com.chet.tweaks.tests", key: "location", type: .string),
            control: .folder)
        let inside = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop").path
        #expect(TweakEngine.state(for: tweak, current: .string(inside)) == .value("~/Desktop"))
        #expect(TweakEngine.state(for: tweak, current: .string("/Volumes/Shots")) == .value("/Volumes/Shots"))
    }

    // MARK: Catalog

    @Test func catalogIsCompleteAndConsistent() {
        let all = TweakCatalog.all
        #expect(all.count >= 25)
        #expect(Set(all.map(\.id)).count == all.count)

        for tweak in all {
            #expect(!tweak.id.isEmpty)
            #expect(!tweak.name.isEmpty)
            #expect(!tweak.summary.isEmpty)
            #expect(!tweak.detail.isEmpty)
            #expect(!tweak.impact.isEmpty)
            #expect(!tweak.configurationLabel.isEmpty)

            let type: TweakValueType
            switch tweak.target {
            case .defaults(_, _, let declared): type = declared
            case .fileHidden: type = .boolean
            }

            switch tweak.control {
            case .toggle(let on, let off):
                #expect(on.type == type, "\(tweak.id): on value does not match the key type")
                if let off { #expect(off.type == type, "\(tweak.id): off value does not match") }
            case .choice(let options):
                #expect(options.count >= 2, "\(tweak.id): a choice needs two options")
                for option in options {
                    #expect(option.value.type == type, "\(tweak.id): option type mismatch")
                }
            case .folder:
                #expect(type == .string, "\(tweak.id): a folder needs a string key")
            }

            if let fallback = tweak.defaultValue {
                #expect(fallback.type == type, "\(tweak.id): default type mismatch")
                if case .choice(let options) = tweak.control {
                    #expect(options.contains { $0.value == fallback }, "\(tweak.id): default is not an option")
                }
            }
        }
    }

    @Test func catalogCoversEveryCategory() {
        let categories = Set(TweakCatalog.all.map(\.category))
        #expect(categories == Set(TweakCategory.allCases))
    }

    // MARK: History

    @Test func historyRoundTripsNewestLast() throws {
        let dir = try TempDir()
        let history = TweakHistory(url: dir.url.appendingPathComponent("tweaks.log"))
        let first = TweakRecord(
            tweakID: "a", at: Date(timeIntervalSince1970: 1_760_000_000), action: .set,
            before: nil, after: .boolean(true))
        let second = TweakRecord(
            tweakID: "b", at: Date(timeIntervalSince1970: 1_760_000_100), action: .reset,
            before: .integer(2), after: nil)
        history.append(first)
        history.append(second)

        let loaded = history.load()
        #expect(loaded == [first, second])
        #expect(history.last(for: "a") == first)
        #expect(history.last(for: "zzz") == nil)
    }

    // MARK: Live defaults

    @Test func setVerifyResetAgainstAProbeDomain() throws {
        let dir = try TempDir()
        let history = TweakHistory(url: dir.url.appendingPathComponent("tweaks.log"))
        let probe = domain()
        let tweak = toggleTweak(domain: probe)
        defer { _ = Subprocess.run("/usr/bin/defaults", ["delete", probe]) }

        // Start from absent.
        #expect(TweakEngine.read(tweak).current == nil)

        let turnedOn = TweakEngine.set(tweak, to: .boolean(true), history: history, dryRun: false)
        #expect(turnedOn.record.error == nil)
        #expect(turnedOn.reading.current == .boolean(true))
        #expect(turnedOn.reading.state == .on)
        #expect(turnedOn.reading.isCustomized)
        #expect(turnedOn.record.before == nil)

        let turnedOff = TweakEngine.set(tweak, to: .boolean(false), history: history, dryRun: false)
        #expect(turnedOff.record.error == nil)
        #expect(turnedOff.reading.current == .boolean(false))
        #expect(turnedOff.record.before == .boolean(true))

        let reset = TweakEngine.reset(tweak, history: history, dryRun: false)
        #expect(reset.record.error == nil)
        #expect(reset.reading.current == nil)
        #expect(reset.record.action == .reset)

        #expect(history.load().count == 3)
    }

    @Test func mediumRiskNeedsConfirmationAndWritesNothing() throws {
        let dir = try TempDir()
        let history = TweakHistory(url: dir.url.appendingPathComponent("tweaks.log"))
        let probe = domain()
        let tweak = Tweak(
            id: "test.confirm", category: .windows, name: "Risky", summary: "Summary",
            detail: "Detail", impact: "Impact", risk: .medium,
            target: .defaults(domain: probe, key: "risky", type: .boolean),
            control: .toggle(on: .boolean(true), off: .boolean(false)))
        defer { _ = Subprocess.run("/usr/bin/defaults", ["delete", probe]) }

        let blocked = TweakEngine.set(tweak, to: .boolean(true), history: history, dryRun: false)
        #expect(blocked.record.error?.contains("confirmation") == true)
        #expect(TweakEngine.read(tweak).current == nil)

        let allowed = TweakEngine.set(
            tweak, to: .boolean(true), confirmed: true, history: history, dryRun: false)
        #expect(allowed.record.error == nil)
        #expect(allowed.reading.current == .boolean(true))
    }

    @Test func dryRunRefusesTheWriteAndRecordsNothing() throws {
        let dir = try TempDir()
        let history = TweakHistory(url: dir.url.appendingPathComponent("tweaks.log"))
        let probe = domain()
        let tweak = toggleTweak(domain: probe)
        defer { _ = Subprocess.run("/usr/bin/defaults", ["delete", probe]) }

        let gated = TweakEngine.set(tweak, to: .boolean(true), history: history, dryRun: true)
        #expect(gated.record.error == TweakError.gated.message)
        #expect(gated.reading.current == nil)
        #expect(history.load().isEmpty)
        #expect(TweakEngine.read(tweak).current == nil)

        let reset = TweakEngine.reset(tweak, history: history, dryRun: true)
        #expect(reset.record.error == TweakError.gated.message)
        #expect(history.load().isEmpty)
        #expect(!TweakEngine.restart(.finder, dryRun: true))
    }

    @Test func fileHiddenFlagRoundTrips() throws {
        let dir = try TempDir()
        let path = dir.url.appendingPathComponent("Library").path
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        let history = TweakHistory(url: dir.url.appendingPathComponent("tweaks.log"))
        let tweak = Tweak(
            id: "test.hidden", category: .finder, name: "Hidden", summary: "Summary",
            detail: "Detail", impact: "Impact", target: .fileHidden(path: path),
            control: .toggle(on: .boolean(false), off: .boolean(true)),
            defaultValue: .boolean(false))

        #expect(TweakEngine.read(tweak).state == .on)

        let hidden = TweakEngine.set(tweak, to: .boolean(true), history: history, dryRun: false)
        #expect(hidden.record.error == nil)
        #expect(hidden.reading.state == .off)
        #expect(hidden.reading.isCustomized)

        let shown = TweakEngine.set(tweak, to: .boolean(false), history: history, dryRun: false)
        #expect(shown.reading.state == .on)
        #expect(!shown.reading.isCustomized)
    }

    // MARK: Helpers

    private func domain() -> String {
        "com.chet.tweaks.tests.\(UUID().uuidString)"
    }

    private func toggleTweak(domain: String) -> Tweak {
        Tweak(
            id: "test.toggle", category: .finder, name: "Name", summary: "Summary",
            detail: "Detail", impact: "Impact",
            target: .defaults(domain: domain, key: "probe", type: .boolean),
            control: .toggle(on: .boolean(true), off: .boolean(false)),
            defaultValue: .boolean(false))
    }
}

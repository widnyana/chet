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

    @Test func correctedRowsShowTheirDeclaredDefault() throws {
        let extensions = try #require(TweakCatalog.all.first { $0.id == "finder.extensions" })
        #expect(TweakEngine.state(for: extensions, current: nil) == .off)
        let search = try #require(TweakCatalog.all.first { $0.id == "finder.search-current" })
        #expect(TweakEngine.state(for: search, current: nil) == .value("This Mac"))
        let network = try #require(TweakCatalog.all.first { $0.id == "finder.ds-store-network" })
        #expect(TweakEngine.state(for: network, current: nil) == .off)
        let period = try #require(TweakCatalog.all.first { $0.id == "keyboard.double-space-period" })
        #expect(TweakEngine.state(for: period, current: nil) == .on)
        let completion = try #require(TweakCatalog.all.first { $0.id == "keyboard.text-completion" })
        #expect(TweakEngine.state(for: completion, current: nil) == .off)
    }

    @Test func customizedMeansWrittenAndDifferentFromDefault() {
        let tweak = toggleTweak(domain: domain())
        #expect(!TweakReading(tweak: tweak, state: .off, current: nil).isCustomized)
        #expect(!TweakReading(tweak: tweak, state: .off, current: .boolean(false)).isCustomized)
        #expect(TweakReading(tweak: tweak, state: .on, current: .boolean(true)).isCustomized)
    }

    @Test func defaultDisplayRendersTheDeclaredValue() {
        let on: TweakValue? = .boolean(true)
        let format: TweakValue? = .string("Dark")
        let count: TweakValue? = .integer(3)
        let missing: TweakValue? = nil
        #expect(on.defaultDisplay == "On")
        #expect(format.defaultDisplay == "Dark")
        #expect(count.defaultDisplay == "3")
        #expect(missing.defaultDisplay == "Not set")
    }

    @Test func absentKeyIsNotCustomized() {
        let tweak = toggleTweak(domain: domain())
        let reading = TweakReading(
            tweak: tweak, state: TweakEngine.state(for: tweak, current: nil), current: nil)
        #expect(!reading.isCustomized)
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

    @Test func resolvedRowsCarryTheMeasuredDefaults() throws {
        let reveal = try #require(TweakCatalog.all.first { $0.id == "dock.reveal-delay" })
        #expect(reveal.defaultValue == .number(0.2))
        #expect(!reveal.detail.contains { $0.isNumber })
        #expect(!reveal.detail.lowercased().contains("second"))

        let location = try #require(TweakCatalog.all.first { $0.id == "screenshots.location" })
        #expect(location.defaultValue == .string("~/Desktop"))
        #expect(location.restart == .systemUI)

        #expect(!TweakCatalog.all.contains { $0.id == "dock.hidden-apps" })
    }

    @Test func normalizedMapsHomePathsToTilde() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        #expect(
            TweakEngine.normalized(.string("\(home)/Desktop"), for: .folder) == .string("~/Desktop"))
        #expect(TweakEngine.normalized(.string("~/Desktop"), for: .folder) == .string("~/Desktop"))
        #expect(
            TweakEngine.normalized(.string("/Volumes/Other"), for: .folder)
                == .string("/Volumes/Other"))
        #expect(
            TweakEngine.normalized(.string("\(home)/Desktop"), for: .text(placeholder: "x"))
                == .string("\(home)/Desktop"))
    }

    @Test func folderRoundTripRecordsTildeForm() throws {
        let dir = try TempDir()
        let history = TweakHistory(url: dir.url.appendingPathComponent("tweaks.log"))
        let probe = try prefsDomain(dir)
        let tweak = Tweak(
            id: "test.folder-round-trip", category: .screenshots, name: "Folder",
            summary: "Summary", detail: "Detail", impact: "Impact",
            target: .defaults(domain: probe, key: "location", type: .string),
            control: .folder)
        let desktop = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop").path
        let change = TweakEngine.set(tweak, to: .string(desktop), history: history, dryRun: false)
        #expect(change.record.error == nil)
        #expect(change.reading.current == .string("~/Desktop"))
        #expect(change.record.after == .string("~/Desktop"))
    }

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

            let type: TweakValueType?
            switch tweak.target {
            case .defaults(_, _, let declared): type = declared
            case .fileHidden: type = .boolean
            case .probe: type = nil
            }

            switch tweak.control {
            case .toggle(let on, let off):
                #expect(type != nil, "\(tweak.id): a toggle needs a value target")
                #expect(on.type == type, "\(tweak.id): on value does not match the key type")
                if let off { #expect(off.type == type, "\(tweak.id): off value does not match") }
            case .choice(let options):
                #expect(options.count >= 2, "\(tweak.id): a choice needs two options")
                for option in options {
                    #expect(option.value.type == type, "\(tweak.id): option type mismatch")
                }
            case .folder:
                #expect(type == .string, "\(tweak.id): a folder needs a string key")
            case .range:
                #expect(
                    type == .integer || type == .number,
                    "\(tweak.id): a range needs a numeric key")
            case .text:
                #expect(type == .string, "\(tweak.id): text needs a string key")
            case .inspect:
                #expect(type == nil, "\(tweak.id): an inspect control must use a probe target")
            }

            for companion in tweak.companions {
                guard case .defaults(_, _, let companionType) = companion else {
                    Issue.record("\(tweak.id): a companion must be a defaults target")
                    continue
                }
                guard case .toggle(let on, _) = tweak.control else {
                    Issue.record("\(tweak.id): companions need a toggle control")
                    continue
                }
                #expect(on.type == companionType, "\(tweak.id): companion type mismatch")
            }

            if let fallback = tweak.defaultValue, let type {
                #expect(fallback.type == type, "\(tweak.id): default type mismatch")
                if case .choice(let options) = tweak.control {
                    #expect(options.contains { $0.value == fallback }, "\(tweak.id): default is not an option")
                }
            }

            if tweak.control == .inspect {
                guard case .probe = tweak.target else {
                    Issue.record("\(tweak.id): an inspect control must use a probe target")
                    continue
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
        let probe = try prefsDomain(dir)
        let tweak = toggleTweak(domain: probe)

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
        let probe = try prefsDomain(dir)
        let tweak = Tweak(
            id: "test.confirm", category: .windows, name: "Risky", summary: "Summary",
            detail: "Detail", impact: "Impact", risk: .medium,
            target: .defaults(domain: probe, key: "risky", type: .boolean),
            control: .toggle(on: .boolean(true), off: .boolean(false)))

        let blocked = TweakEngine.set(tweak, to: .boolean(true), history: history, dryRun: false)
        #expect(blocked.needsConfirmation)
        #expect(blocked.record.error?.contains("confirmation") == true)
        #expect(history.load().isEmpty)
        #expect(TweakEngine.read(tweak).current == nil)

        let allowed = TweakEngine.set(
            tweak, to: .boolean(true), confirmed: true, history: history, dryRun: false)
        #expect(allowed.record.error == nil)
        #expect(allowed.reading.current == .boolean(true))
    }

    @Test func dryRunRefusesTheWriteAndRecordsNothing() throws {
        let dir = try TempDir()
        let history = TweakHistory(url: dir.url.appendingPathComponent("tweaks.log"))
        let probe = try prefsDomain(dir)
        let tweak = toggleTweak(domain: probe)

        let gated = TweakEngine.set(tweak, to: .boolean(true), history: history, dryRun: true)
        #expect(gated.record.error == TweakError.gated.message)
        #expect(gated.reading.current == nil)
        #expect(history.load().isEmpty)
        #expect(TweakEngine.read(tweak).current == nil)

        let reset = TweakEngine.reset(tweak, history: history, dryRun: true)
        #expect(reset.record.error == TweakError.gated.message)
        #expect(history.load().isEmpty)
        #expect(!TweakEngine.restart(.finder, dryRun: true))

        // The gate also precedes the unsupported failure, which would otherwise write a
        // failure record for a path that does not exist.
        let missing = Tweak(
            id: "test.missing", category: .finder, name: "Missing", summary: "Summary",
            detail: "Detail", impact: "Impact",
            target: .fileHidden(path: dir.url.appendingPathComponent("nope").path),
            control: .toggle(on: .boolean(false), off: .boolean(true)),
            defaultValue: .boolean(false))
        let gatedUnsupported = TweakEngine.set(missing, to: .boolean(true), history: history, dryRun: true)
        #expect(gatedUnsupported.record.error == TweakError.gated.message)
        #expect(history.load().isEmpty)
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

    // MARK: Probes

    @Test func parseProbeMapsEveryOutput() {
        #expect(TweakEngine.parseProbe("Firewall is enabled. (State = 1)", for: .firewall) == .on)
        #expect(TweakEngine.parseProbe("Firewall is disabled. (State = 0)", for: .firewall) == .off)
        #expect(TweakEngine.parseProbe("FileVault is On.", for: .fileVault) == .on)
        #expect(TweakEngine.parseProbe("FileVault is Off.", for: .fileVault) == .off)
        #expect(TweakEngine.parseProbe("assessments enabled", for: .gatekeeper) == .on)
        #expect(TweakEngine.parseProbe("assessments disabled", for: .gatekeeper) == .off)
        #expect(TweakEngine.parseProbe("1", for: .automaticUpdates) == .on)
        #expect(TweakEngine.parseProbe("0", for: .automaticUpdates) == .off)
        #expect(
            TweakEngine.parseProbe("/Library/Developer/CommandLineTools", for: .xcodeTools)
                == .value("/Library/Developer/CommandLineTools"))
        #expect(TweakEngine.parseProbe("UserShell: /bin/zsh", for: .loginShell) == .value("/bin/zsh"))
        #expect(TweakEngine.parseProbe("Homebrew 4.6.1", for: .homebrew) == .value("Homebrew 4.6.1"))
        #expect(TweakEngine.parseProbe("1", for: .virtualization) == .value("Supported"))
        #expect(TweakEngine.parseProbe("0", for: .virtualization) == .value("Not supported"))
        #expect(TweakEngine.parseProbe("something else", for: .firewall) == nil)
    }

    @Test func probeReadingsComeBackFromThisMac() throws {
        for id in ["developer.virtualization", "developer.homebrew", "developer.login-shell"] {
            let tweak = try #require(TweakCatalog.all.first { $0.id == id })
            let reading = TweakEngine.read(tweak)
            #expect(reading.isSupported, "\(id) should be readable on this Mac")
            if case .unknown(let reason) = reading.state {
                Issue.record("\(id) is unknown: \(reason)")
            }
        }
    }

    @Test func inspectionTweaksRefuseWrites() throws {
        let dir = try TempDir()
        let history = TweakHistory(url: dir.url.appendingPathComponent("tweaks.log"))
        let tweak = try #require(TweakCatalog.all.first { $0.id == "security.firewall" })
        let change = TweakEngine.set(tweak, to: .boolean(true), history: history, dryRun: false)
        #expect(change.record.error == TweakError.inspectionOnly.message)
        #expect(!change.needsConfirmation)
        #expect(history.load().isEmpty)
        let reset = TweakEngine.reset(tweak, history: history, dryRun: false)
        #expect(reset.record.error == TweakError.inspectionOnly.message)
        #expect(history.load().isEmpty)
    }

    // MARK: Lifecycle

    @Test func unchangedWriteIsNotRecorded() throws {
        let dir = try TempDir()
        let history = TweakHistory(url: dir.url.appendingPathComponent("tweaks.log"))
        let probe = try prefsDomain(dir)
        let tweak = toggleTweak(domain: probe)

        let first = TweakEngine.set(tweak, to: .boolean(true), history: history, dryRun: false)
        #expect(!first.unchanged)
        let second = TweakEngine.set(tweak, to: .boolean(true), history: history, dryRun: false)
        #expect(second.unchanged)
        #expect(second.record.error == nil)
        #expect(history.load().count == 1)
    }

    @Test func companionsWriteVerifyAndRestore() throws {
        let dir = try TempDir()
        let history = TweakHistory(url: dir.url.appendingPathComponent("tweaks.log"))
        let primary = try prefsDomain(dir)
        let companion = try prefsDomain(dir)
        let tweak = Tweak(
            id: "test.companions", category: .keyboard, name: "Companion", summary: "Summary",
            detail: "Detail", impact: "Impact",
            target: .defaults(domain: primary, key: "on", type: .boolean),
            control: .toggle(on: .boolean(true), off: .boolean(false)),
            companions: [.defaults(domain: companion, key: "on", type: .boolean)],
            defaultValue: .boolean(false))

        let first = TweakEngine.set(tweak, to: .boolean(true), history: history, dryRun: false)
        #expect(first.record.error == nil)
        #expect(TweakEngine.read(tweak).current == .boolean(true))
        #expect(TweakEngine.companionValues(tweak) == [.boolean(true)])

        let off = TweakEngine.set(tweak, to: .boolean(false), history: history, dryRun: false)
        #expect(off.reading.current == .boolean(false))
        #expect(TweakEngine.companionValues(tweak) == [.boolean(false)])

        let rolledBack = TweakEngine.rollback(off.record, tweak: tweak, history: history, dryRun: false)
        #expect(rolledBack.record.error == nil)
        #expect(rolledBack.reading.current == .boolean(true))
        #expect(TweakEngine.companionValues(tweak) == [.boolean(true)])
        #expect(history.load().last?.action == .rollback)
    }

    @Test func rollbackRefusesAMismatchedRecord() throws {
        let dir = try TempDir()
        let history = TweakHistory(url: dir.url.appendingPathComponent("tweaks.log"))
        let probe = try prefsDomain(dir)
        let tweak = Tweak(
            id: "test.integer", category: .keyboard, name: "Number", summary: "Summary",
            detail: "Detail", impact: "Impact",
            target: .defaults(domain: probe, key: "n", type: .integer),
            control: .range(min: 1, max: 15, step: 1, unit: nil),
            defaultValue: .integer(6))
        let bad = TweakRecord(tweakID: tweak.id, action: .set, before: .string("wrong"), after: nil)
        let change = TweakEngine.rollback(bad, tweak: tweak, history: history, dryRun: false)
        #expect(change.record.error?.contains("does not match") == true)
        #expect(TweakEngine.read(tweak).current == nil)
        #expect(history.load().isEmpty)
    }

    @Test func rangeAndTextControlsWriteTypedValues() throws {
        let dir = try TempDir()
        let history = TweakHistory(url: dir.url.appendingPathComponent("tweaks.log"))
        let numberDomain = try prefsDomain(dir)
        let textDomain = try prefsDomain(dir)

        let ranged = Tweak(
            id: "test.range", category: .keyboard, name: "Rate", summary: "Summary",
            detail: "Detail", impact: "Impact",
            target: .defaults(domain: numberDomain, key: "rate", type: .integer),
            control: .range(min: 1, max: 15, step: 1, unit: nil),
            defaultValue: .integer(6))
        let number = TweakEngine.set(ranged, to: .integer(9), history: history, dryRun: false)
        #expect(number.reading.current == .integer(9))
        #expect(number.reading.state == .value("9"))

        let texted = Tweak(
            id: "test.text", category: .screenshots, name: "Name", summary: "Summary",
            detail: "Detail", impact: "Impact",
            target: .defaults(domain: textDomain, key: "name", type: .string),
            control: .text(placeholder: "Screenshot"),
            defaultValue: .string("Screenshot"))
        let text = TweakEngine.set(texted, to: .string("Shot"), history: history, dryRun: false)
        #expect(text.reading.current == .string("Shot"))
        #expect(text.reading.state == .value("Shot"))
        #expect(text.reading.isCustomized)
    }

    // MARK: Helpers

    private func domain() -> String {
        "com.chet.tweaks.tests.\(UUID().uuidString)"
    }

    private func prefsDomain(_ dir: TempDir) throws -> String {
        let folder = dir.url.appendingPathComponent("prefs")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent(UUID().uuidString).path
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

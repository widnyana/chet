import Foundation
import Testing

@testable import ChetCore

struct TweakAutomationTests {
    @Test func resolvedValueIsTotalOverToggles() {
        for tweak in TweakCatalog.all {
            switch tweak.control {
            case .toggle(let on, let off):
                #expect(tweak.control.resolvedValue(for: .on) == on)
                #expect(tweak.control.resolvedValue(for: .off) == off)
            default:
                #expect(tweak.control.resolvedValue(for: .on) == nil)
                #expect(tweak.control.resolvedValue(for: .off) == nil)
            }
        }
    }

    @Test func resolvedValueDeletesTheKeyWhenOffIsAbsent() {
        let control = TweakControl.toggle(on: .boolean(true), off: nil)
        #expect(control.resolvedValue(for: .on) == .boolean(true))
        #expect(control.resolvedValue(for: .off) == nil)
    }

    private func rule(
        _ tweakID: String, desired: TweakDesired = .on, enabled: Bool = true,
        bundleID: String = "com.example.app"
    ) -> TweakRule {
        TweakRule(
            tweakID: tweakID, trigger: .app(bundleID: bundleID, name: "Example"),
            desired: desired, isEnabled: enabled)
    }

    @Test func desiredMarksDisabledRulesFalse() {
        let enabled = rule("finder.hidden-files")
        let disabled = rule("finder.hidden-files", enabled: false)
        let map = AutomationPlanner.desired(rules: [enabled, disabled], running: ["com.example.app"])
        #expect(map[enabled.id] == true)
        #expect(map[disabled.id] == false)
    }

    @Test func planAppliesWhenEnabledAndRunning() {
        let rule = rule("finder.hidden-files")
        let decisions = AutomationPlanner.plan(
            rules: [rule], running: ["com.example.app"], state: WALState(),
            current: [TweakCurrent(tweakID: "finder.hidden-files", value: .boolean(false))])
        #expect(decisions == [.apply(ruleID: rule.id, value: .boolean(true))])
    }

    @Test func planKeepsWhenAlreadyDesired() {
        let rule = rule("finder.hidden-files")
        let decisions = AutomationPlanner.plan(
            rules: [rule], running: ["com.example.app"], state: WALState(),
            current: [TweakCurrent(tweakID: "finder.hidden-files", value: .boolean(true))])
        #expect(decisions == [.keep(tweakID: "finder.hidden-files")])
    }

    @Test func planKeepsWhenReadingMissing() {
        let rule = rule("finder.hidden-files")
        let decisions = AutomationPlanner.plan(
            rules: [rule], running: ["com.example.app"], state: WALState(), current: [])
        #expect(decisions == [.keep(tweakID: "finder.hidden-files")])
    }

    @Test func planOrphansAnUnknownTweak() {
        let rule = rule("no.such.tweak")
        let decisions = AutomationPlanner.plan(
            rules: [rule], running: ["com.example.app"], state: WALState(),
            current: [TweakCurrent(tweakID: "no.such.tweak", value: nil)])
        #expect(decisions == [.orphan(tweakID: "no.such.tweak")])
    }

    @Test func planOrphansANonToggle() {
        let rule = rule("screenshots.format")
        let decisions = AutomationPlanner.plan(
            rules: [rule], running: ["com.example.app"], state: WALState(),
            current: [TweakCurrent(tweakID: "screenshots.format", value: .string("png"))])
        #expect(decisions == [.orphan(tweakID: "screenshots.format")])
    }

    @Test func planRevertsWhenTheRuleTurnsOff() {
        let rule = rule("finder.hidden-files", enabled: false)
        let state = WALState(applied: [
            "finder.hidden-files": .init(
                ruleID: rule.id, tweakID: "finder.hidden-files", appliedValue: .boolean(true),
                baseline: .boolean(false), baselineSource: "engine", phase: "applied",
                appliedAt: Date(timeIntervalSince1970: 1), conflict: nil)
        ])
        let decisions = AutomationPlanner.plan(
            rules: [rule], running: ["com.example.app"], state: state,
            current: [TweakCurrent(tweakID: "finder.hidden-files", value: .boolean(true))])
        #expect(decisions == [.revert(tweakID: "finder.hidden-files", value: .boolean(false))])
    }

    @Test func planConflictsOnAManualChange() {
        let rule = rule("finder.hidden-files", enabled: false)
        let state = WALState(applied: [
            "finder.hidden-files": .init(
                ruleID: rule.id, tweakID: "finder.hidden-files", appliedValue: .boolean(true),
                baseline: .boolean(false), baselineSource: "engine", phase: "applied",
                appliedAt: Date(timeIntervalSince1970: 1), conflict: nil)
        ])
        let decisions = AutomationPlanner.plan(
            rules: [rule], running: ["com.example.app"], state: state,
            current: [TweakCurrent(tweakID: "finder.hidden-files", value: .string("manual"))])
        #expect(decisions == [.conflict(tweakID: "finder.hidden-files")])
    }

    @Test func appearanceDarkOffResolvesToNil() throws {
        let tweak = try #require(TweakCatalog.tweak(id: "appearance.dark"))
        #expect(tweak.control.resolvedValue(for: .off) == nil)
        let rule = rule("appearance.dark", desired: .off)
        let decisions = AutomationPlanner.plan(
            rules: [rule], running: ["com.example.app"], state: WALState(),
            current: [TweakCurrent(tweakID: "appearance.dark", value: .string("Dark"))])
        #expect(decisions == [.apply(ruleID: rule.id, value: nil)])
    }

    @Test func rulesRoundTrip() throws {
        let dir = try TempDir()
        let store = TriggerStore(url: dir.url.appendingPathComponent("rules.json"))
        let rules = [rule("finder.hidden-files"), rule("dock.autohide", desired: .off, enabled: false)]
        #expect(store.save(rules) == nil)
        let loaded = store.load()
        #expect(loaded.error == nil)
        #expect(loaded.payload == rules)
    }

    @Test func envelopeCarriesVersionOne() throws {
        let dir = try TempDir()
        let url = dir.url.appendingPathComponent("rules.json")
        let store = TriggerStore(url: url)
        #expect(store.save([rule("finder.hidden-files")]) == nil)
        let data = try Data(contentsOf: url)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["version"] as? Int == 1)
    }

    @Test func secondSaveLeavesABackup() throws {
        let dir = try TempDir()
        let url = dir.url.appendingPathComponent("rules.json")
        let store = TriggerStore(url: url)
        let first = [rule("finder.hidden-files")]
        let second = [rule("dock.autohide")]
        #expect(store.save(first) == nil)
        #expect(store.save(second) == nil)
        #expect(store.load().payload == second)
        let backup = TriggerStore(url: url.appendingPathExtension("bak")).load()
        #expect(backup.payload == first)
    }

    @Test func corruptFileIsQuarantined() throws {
        let dir = try TempDir()
        let url = dir.url.appendingPathComponent("rules.json")
        try Data("not json".utf8).write(to: url)
        let loaded = TriggerStore(url: url).load()
        #expect(loaded.payload.isEmpty)
        #expect(loaded.error == .corrupt(url))
        #expect(FileManager.default.fileExists(atPath: url.appendingPathExtension("corrupt").path))
    }

    @Test func absentFileLoadsEmpty() throws {
        let dir = try TempDir()
        let url = dir.url.appendingPathComponent("rules.json")
        let loaded = TriggerStore(url: url).load()
        #expect(loaded.payload.isEmpty)
        #expect(loaded.error == nil)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func walRoundTripsEveryShape() throws {
        let dir = try TempDir()
        let store = WALStore(url: dir.url.appendingPathComponent("state.json"))
        let ruleID = UUID()
        let state = WALState(applied: [
            "finder.hidden-files": .init(
                ruleID: ruleID, tweakID: "finder.hidden-files", appliedValue: .boolean(true),
                baseline: .boolean(false), baselineSource: "engine", phase: "applied",
                appliedAt: Date(timeIntervalSince1970: 1), conflict: nil),
            "appearance.dark": .init(
                ruleID: ruleID, tweakID: "appearance.dark", appliedValue: nil,
                baseline: .string("Light"), baselineSource: "engine", phase: "reverting",
                appliedAt: Date(timeIntervalSince1970: 2), conflict: "manual"),
        ])
        #expect(store.save(state) == nil)
        let loaded = store.load()
        #expect(loaded.error == nil)
        #expect(loaded.payload == state)
        #expect(loaded.payload.applied["appearance.dark"]?.appliedValue == nil)
    }

    @Test func defaultURLsFollowTheProductionPath() {
        #expect(
            TriggerStore.defaultURL.path.hasSuffix(
                "Library/Application Support/Chet/tweak-automation-rules.json"))
        #expect(
            WALStore.defaultURL.path.hasSuffix(
                "Library/Application Support/Chet/tweak-automation-state.json"))
    }

    @Test func executorAppliesAndRecordsTheEngineBaseline() async {
        let rule = rule("finder.hidden-files")
        let record = TweakRecord(
            tweakID: "finder.hidden-files", action: .set, before: .boolean(false),
            after: .boolean(true))
        let engine = FakeEngine(
            currents: ["finder.hidden-files": .boolean(false)],
            outcomes: ["finder.hidden-files": .applied(recorded: record)])
        let executor = AutomationExecutor(
            rules: [rule], state: WALState(), engine: engine, dryRun: false)
        let result = await executor.reconcile(running: ["com.example.app"])
        let calls = await engine.calls
        #expect(calls == ["apply:finder.hidden-files"])
        #expect(result.state.applied["finder.hidden-files"]?.phase == "applied")
        #expect(result.state.applied["finder.hidden-files"]?.baselineSource == "engine")
    }

    @Test func executorRemovesTheEntryOnRefusal() async {
        let rule = rule("finder.hidden-files")
        let engine = FakeEngine(
            currents: ["finder.hidden-files": .boolean(false)],
            outcomes: ["finder.hidden-files": .refused("no")])
        let executor = AutomationExecutor(
            rules: [rule], state: WALState(), engine: engine, dryRun: false)
        let result = await executor.reconcile(running: ["com.example.app"])
        #expect(result.state.applied["finder.hidden-files"] == nil)
    }

    @Test func executorRevertsAndRemovesTheEntry() async {
        let rule = rule("finder.hidden-files", enabled: false)
        let state = WALState(applied: [
            "finder.hidden-files": .init(
                ruleID: rule.id, tweakID: "finder.hidden-files", appliedValue: .boolean(true),
                baseline: .boolean(false), baselineSource: "engine", phase: "applied",
                appliedAt: Date(timeIntervalSince1970: 1), conflict: nil)
        ])
        let engine = FakeEngine(
            currents: ["finder.hidden-files": .boolean(true)],
            outcomes: ["finder.hidden-files": .applied(recorded: nil)])
        let executor = AutomationExecutor(
            rules: [rule], state: state, engine: engine, dryRun: false)
        let result = await executor.reconcile(running: ["com.example.app"])
        let calls = await engine.calls
        #expect(calls == ["revert:finder.hidden-files"])
        #expect(result.state.applied["finder.hidden-files"] == nil)
    }

    @Test func executorKeepsTheEntryOnAFailedRevert() async {
        let rule = rule("finder.hidden-files", enabled: false)
        let state = WALState(applied: [
            "finder.hidden-files": .init(
                ruleID: rule.id, tweakID: "finder.hidden-files", appliedValue: .boolean(true),
                baseline: .boolean(false), baselineSource: "engine", phase: "applied",
                appliedAt: Date(timeIntervalSince1970: 1), conflict: nil)
        ])
        let engine = FakeEngine(
            currents: ["finder.hidden-files": .boolean(true)],
            outcomes: ["finder.hidden-files": .failed("no")])
        let executor = AutomationExecutor(
            rules: [rule], state: state, engine: engine, dryRun: false)
        let result = await executor.reconcile(running: ["com.example.app"])
        #expect(result.state.applied["finder.hidden-files"]?.phase == "reverting")
    }

    @Test func dryRunCallsNoEngineWrite() async {
        let rule = rule("finder.hidden-files")
        let engine = FakeEngine(currents: ["finder.hidden-files": .boolean(false)])
        let executor = AutomationExecutor(
            rules: [rule], state: WALState(), engine: engine, dryRun: true)
        let result = await executor.reconcile(running: ["com.example.app"])
        let calls = await engine.calls
        #expect(calls.isEmpty)
        #expect(result.state == WALState())
        #expect(result.decisions == [.apply(ruleID: rule.id, value: .boolean(true))])
    }

    @Test func sessionStartsInOrder() async {
        let order = OrderRecorder()
        let session = AutomationSession(
            loadRules: {
                order.append("rules")
                return []
            },
            loadState: {
                order.append("state")
                return WALState()
            },
            running: {
                order.append("running")
                return []
            },
            reconcile: { _ in
                order.append("reconcile")
                return (WALState(), [])
            })
        _ = await session.start()
        #expect(order.values == ["rules", "state", "running", "reconcile"])
    }
}

private actor FakeEngine: TweakAutomationEngine {
    private let currents: [String: TweakValue?]
    private let outcomes: [String: AutomationEngineOutcome]
    private var recorded: [String] = []

    init(
        currents: [String: TweakValue?] = [:],
        outcomes: [String: AutomationEngineOutcome] = [:]
    ) {
        self.currents = currents
        self.outcomes = outcomes
    }

    var calls: [String] { recorded }

    func current(tweakID: String) async -> TweakCurrent? {
        guard let value = currents[tweakID] else { return nil }
        return TweakCurrent(tweakID: tweakID, value: value)
    }

    func apply(tweakID: String, value: TweakValue?) async -> AutomationEngineOutcome {
        recorded.append("apply:\(tweakID)")
        return outcomes[tweakID] ?? .applied(recorded: nil)
    }

    func revert(tweakID: String, to value: TweakValue?) async -> AutomationEngineOutcome {
        recorded.append("revert:\(tweakID)")
        return outcomes[tweakID] ?? .applied(recorded: nil)
    }
}

private final class OrderRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String] = []

    var values: [String] {
        lock.lock()
        defer { lock.unlock() }
        return items
    }

    func append(_ value: String) {
        lock.lock()
        items.append(value)
        lock.unlock()
    }
}

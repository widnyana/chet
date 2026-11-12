import Foundation

// MARK: - Values

/// The declared type of a tweak's stored value. It decides how `defaults read` output is
/// parsed and which flag `defaults write` receives.
public enum TweakValueType: String, Codable, Sendable, Hashable {
    case boolean
    case integer
    case number
    case string
}

public enum TweakValue: Codable, Sendable, Hashable {
    case boolean(Bool)
    case integer(Int)
    case number(Double)
    case string(String)

    public var type: TweakValueType {
        switch self {
        case .boolean: .boolean
        case .integer: .integer
        case .number: .number
        case .string: .string
        }
    }

    /// A short, readable form for a state line.
    public var display: String {
        switch self {
        case .boolean(let value): value ? "On" : "Off"
        case .integer(let value): "\(value)"
        case .number(let value): String(format: "%g", value)
        case .string(let value): value
        }
    }
}

extension Optional where Wrapped == TweakValue {
    public var defaultDisplay: String {
        self?.display ?? "Not set"
    }
}

// MARK: - Catalog model

public enum TweakCategory: String, CaseIterable, Sendable, Hashable {
    case finder
    case dock
    case keyboard
    case trackpad
    case screenshots
    case appearance
    case windows
    case security
    case developer

    public var title: String {
        switch self {
        case .finder: "Finder"
        case .dock: "Dock"
        case .keyboard: "Keyboard"
        case .trackpad: "Trackpad"
        case .screenshots: "Screenshots"
        case .appearance: "Appearance"
        case .windows: "Windows"
        case .security: "Security"
        case .developer: "Developer"
        }
    }
}

public enum TweakRisk: Int, Codable, Sendable, Comparable, Hashable {
    case low = 0
    case medium = 1
    case high = 2

    public static func < (lhs: TweakRisk, rhs: TweakRisk) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// What has to happen before the change is visible.
public enum TweakRestart: String, Codable, Sendable, Hashable, CaseIterable {
    case none
    case finder
    case dock
    case systemUI
    case login

    /// The process name `killall` takes, or nil when only a login applies.
    public var processName: String? {
        switch self {
        case .none, .login: nil
        case .finder: "Finder"
        case .dock: "Dock"
        case .systemUI: "SystemUIServer"
        }
    }
}

/// A read-only status check for security and developer settings. The engine owns the command
/// or defaults read; the catalog only names the check, so no shell string is data.
public enum TweakProbe: String, Sendable, Hashable, CaseIterable {
    case firewall
    case fileVault
    case gatekeeper
    case automaticUpdates
    case xcodeTools
    case loginShell
    case homebrew
    case virtualization

    public var name: String {
        switch self {
        case .firewall: "Application firewall"
        case .fileVault: "FileVault"
        case .gatekeeper: "Gatekeeper"
        case .automaticUpdates: "Automatic update checks"
        case .xcodeTools: "Xcode command line tools"
        case .loginShell: "Login shell"
        case .homebrew: "Homebrew"
        case .virtualization: "Virtualization support"
        }
    }

    /// What the check reads, shown in the details sheet.
    public var source: String {
        switch self {
        case .firewall: "socketfilterfw --getglobalstate"
        case .fileVault: "fdesetup status"
        case .gatekeeper: "spctl --status"
        case .automaticUpdates: "com.apple.SoftwareUpdate AutomaticCheckEnabled"
        case .xcodeTools: "xcode-select -p"
        case .loginShell: "dscl . -read /Users/<you> UserShell"
        case .homebrew: "Homebrew --version"
        case .virtualization: "sysctl kern.hv_support"
        }
    }

    public var settingsURL: URL? {
        let pane: String
        switch self {
        case .firewall: pane = "x-apple.systempreferences:com.apple.preference.security?Firewall"
        case .fileVault:
            pane = "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_FileVault"
        case .gatekeeper: pane = "x-apple.systempreferences:com.apple.preference.security?Security"
        case .automaticUpdates:
            pane = "x-apple.systempreferences:com.apple.Software-Update-Settings.extension"
        case .xcodeTools:
            pane = "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_DeveloperTools"
        case .loginShell: pane = "x-apple.systempreferences:com.apple.Users-Groups-Settings.extension"
        case .homebrew: return nil
        case .virtualization: return nil
        }
        return URL(string: pane)
    }
}

public enum TweakTarget: Sendable, Hashable {
    /// A key in a preferences domain, such as `com.apple.finder` and `ShowPathbar`.
    case defaults(domain: String, key: String, type: TweakValueType)
    /// The hidden user flag on a path, read with `stat` and written with `chflags`.
    case fileHidden(path: String)
    /// A read-only status check. There is nothing to write.
    case probe(TweakProbe)
}

public struct TweakOption: Sendable, Hashable {
    public let label: String
    public let value: TweakValue

    public init(label: String, value: TweakValue) {
        self.label = label
        self.value = value
    }
}

public enum TweakControl: Sendable, Hashable {
    /// Two named values. A nil `off` means the system default is "the key is absent".
    case toggle(on: TweakValue, off: TweakValue?)
    case choice([TweakOption])
    case folder
    /// A slider. The key type (integer or number) decides how the value is written.
    case range(min: Double, max: Double, step: Double, unit: String?)
    /// A free-text preference, committed when editing ends.
    case text(placeholder: String)
    /// Read-only status with an action that opens the relevant System Settings pane.
    case inspect
}

extension TweakTarget {
    /// The domain and key, path, or check this target reads and writes.
    public var configurationLabel: String {
        switch self {
        case .defaults(let domain, let key, _): "\(domain) · \(key)"
        case .fileHidden(let path): path
        case .probe(let probe): probe.source
        }
    }
}

public struct Tweak: Identifiable, Sendable, Hashable {
    public let id: String
    public let category: TweakCategory
    public let name: String
    /// One sentence under the name.
    public let summary: String
    /// The long explanation, shown in the details sheet.
    public let detail: String
    /// What the change affects, such as "Finder windows".
    public let impact: String
    public let risk: TweakRisk
    public let restart: TweakRestart
    public let target: TweakTarget
    public let control: TweakControl
    /// Additional keys written with the same value, such as the Bluetooth trackpad domain.
    public let companions: [TweakTarget]
    /// The value macOS ships with. Nil means the key is absent by default.
    public let defaultValue: TweakValue?
    public let minimumMajorVersion: Int?

    public init(
        id: String, category: TweakCategory, name: String, summary: String, detail: String,
        impact: String, risk: TweakRisk = .low, target: TweakTarget, control: TweakControl,
        companions: [TweakTarget] = [], defaultValue: TweakValue? = nil,
        restart: TweakRestart = .none, minimumMajorVersion: Int? = nil
    ) {
        self.id = id
        self.category = category
        self.name = name
        self.summary = summary
        self.detail = detail
        self.impact = impact
        self.risk = risk
        self.restart = restart
        self.target = target
        self.control = control
        self.companions = companions
        self.defaultValue = defaultValue
        self.minimumMajorVersion = minimumMajorVersion
    }

    /// The preferences domain and key, or the path, for the details sheet.
    public var configurationLabel: String { target.configurationLabel }
}

// MARK: - State

public enum TweakState: Sendable, Equatable {
    case on
    case off
    case value(String)
    /// A stored value that is not one of the offered options.
    case custom(String)
    case unsupported(String)
    case unknown(String)
    /// The last attempt at this tweak failed. The reading keeps the value read before the
    /// attempt, so the row still shows what the system holds.
    case error(String)
}

public struct TweakReading: Sendable, Identifiable {
    public let tweak: Tweak
    public let state: TweakState
    /// The value the system holds now. Nil means the key is absent.
    public let current: TweakValue?

    public var id: String { tweak.id }

    public init(tweak: Tweak, state: TweakState, current: TweakValue?) {
        self.tweak = tweak
        self.state = state
        self.current = current
    }

    /// The key is written and its behavior differs from the declared macOS default. Comparing
    /// state, not the raw value, keeps a key that macOS writes at its default value (such as a
    /// `0` where absence means the same thing) out of the "changed" count.
    public var isCustomized: Bool {
        guard current != nil else { return false }
        return state != TweakEngine.state(for: tweak, current: tweak.defaultValue)
    }

    public var isSupported: Bool {
        if case .unsupported = state { return false }
        if case .unknown = state { return false }
        return true
    }
}

// MARK: - History

public struct TweakRecord: Codable, Sendable, Identifiable, Equatable {
    public enum Action: String, Codable, Sendable {
        case set
        case reset
        case rollback
    }

    public let id: UUID
    public let tweakID: String
    public let at: Date
    public let action: Action
    public let before: TweakValue?
    public let after: TweakValue?
    /// Values of `Tweak.companions` before the change, in catalog order.
    public let beforeCompanions: [TweakValue?]?
    public let error: String?

    public init(
        id: UUID = UUID(), tweakID: String, at: Date = Date(), action: Action,
        before: TweakValue?, after: TweakValue?, beforeCompanions: [TweakValue?]? = nil,
        error: String? = nil
    ) {
        self.id = id
        self.tweakID = tweakID
        self.at = at
        self.action = action
        self.before = before
        self.after = after
        self.beforeCompanions = beforeCompanions
        self.error = error
    }
}

/// Append-only JSON Lines ledger of tweak changes, newest last.
public struct TweakHistory: Sendable {
    public let url: URL

    public init(
        url: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Chet/tweaks.log")
    ) {
        self.url = url
    }

    public func load() -> [TweakRecord] {
        guard let data = try? Data(contentsOf: url),
            let text = String(data: data, encoding: .utf8)
        else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return text.split(whereSeparator: \.isNewline).compactMap { line in
            try? decoder.decode(TweakRecord.self, from: Data(line.utf8))
        }
    }

    public func append(_ record: TweakRecord) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard var line = try? encoder.encode(record) else { return }
        line.append(0x0A)
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: line)
        } else {
            try? line.write(to: url)
        }
    }

    /// The newest record for one tweak.
    public func last(for tweakID: String) -> TweakRecord? {
        load().last { $0.tweakID == tweakID }
    }
}

// MARK: - Errors

public enum TweakError: Error, Equatable {
    case unsupported(String)
    case unknownState(String)
    case confirmationRequired(String)
    case commandFailed(String)
    case verificationFailed(String)
    case gated
    case inspectionOnly
}

extension TweakError {
    public static let gatedCopy = "Preview only. No tweak is changed."

    public var message: String {
        switch self {
        case .unsupported(let text): text
        case .unknownState(let text): text
        case .confirmationRequired(let text): text
        case .commandFailed(let text): text
        case .verificationFailed(let text): text
        case .gated: Self.gatedCopy
        case .inspectionOnly: "This is a read-only check. Open System Settings to change it."
        }
    }
}

public struct TweakChange: Sendable {
    public let record: TweakRecord
    public let reading: TweakReading
    /// The system already held the requested value. Nothing was written or recorded.
    public let unchanged: Bool
    /// A medium or high risk change that waits for the user to confirm it.
    public let needsConfirmation: Bool
    /// The change was appended to the history ledger. Unchanged, gated, refused, and
    /// unconfirmed changes are never recorded.
    public let recorded: Bool

    public init(
        record: TweakRecord, reading: TweakReading, unchanged: Bool = false,
        needsConfirmation: Bool = false, recorded: Bool = false
    ) {
        self.record = record
        self.reading = reading
        self.unchanged = unchanged
        self.needsConfirmation = needsConfirmation
        self.recorded = recorded
    }
}

// MARK: - Engine

/// Reads, writes, verifies, and records tweak values. Shell tools are the adapter; the
/// catalog stays plain data, so the UI never builds a command string.
public enum TweakEngine {
    static let defaultsTool = "/usr/bin/defaults"
    static let statTool = "/usr/bin/stat"
    static let chflagsTool = "/usr/bin/chflags"
    static let killallTool = "/usr/bin/killall"

    public static func readAll(_ tweaks: [Tweak]) -> [TweakReading] {
        let readings = tweaks.map(read)
        var gated = 0
        for reading in readings where !reading.isSupported {
            gated += 1
        }
        VerboseLog.event(
            .debug, .tweaks, .tweakRead,
            .count(.readings, readings.count),
            .count(.gated, gated))
        return readings
    }

    public static func read(_ tweak: Tweak) -> TweakReading {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        if let minimum = tweak.minimumMajorVersion, version.majorVersion < minimum {
            return TweakReading(
                tweak: tweak, state: .unsupported("Needs macOS \(minimum) or later."), current: nil)
        }

        switch tweak.target {
        case .defaults(let domain, let key, let type):
            switch readDefaults(domain: domain, key: key, type: type) {
            case .success(let value):
                return TweakReading(
                    tweak: tweak, state: state(for: tweak, current: value), current: value)
            case .failure(let error):
                let text = error.localizedDescription
                return TweakReading(tweak: tweak, state: .unknown(text), current: nil)
            }
        case .fileHidden(let path):
            guard FileManager.default.fileExists(atPath: path) else {
                return TweakReading(
                    tweak: tweak, state: .unsupported("\(path) is not on this Mac."), current: nil)
            }
            switch readHidden(path) {
            case .success(let hidden):
                let value = TweakValue.boolean(hidden)
                return TweakReading(tweak: tweak, state: state(for: tweak, current: value), current: value)
            case .failure(let error):
                return TweakReading(
                    tweak: tweak, state: .unknown(error.localizedDescription), current: nil)
            }
        case .probe(let probe):
            return probeReading(tweak, probe: probe)
        }
    }

    /// Writes one value, verifies it by reading it back, and records the change. A failed
    /// verification restores the value from before and records the failure.
    public static func set(
        _ tweak: Tweak, to value: TweakValue?, confirmed: Bool = false,
        history: TweakHistory = TweakHistory(), dryRun: Bool = DryRun.enabled
    ) -> TweakChange {
        VerboseLog.flush()
        return apply(tweak, plan(tweak, value), nil, confirmed: confirmed, history: history, dryRun: dryRun)
    }

    /// The value written to the primary target and to every companion.
    struct TweakPlan: Sendable {
        let primary: TweakValue?
        let companions: [TweakValue?]
    }

    static func plan(_ tweak: Tweak, _ value: TweakValue?) -> TweakPlan {
        TweakPlan(
            primary: value,
            companions: Array(repeating: value, count: tweak.companions.count))
    }

    static func apply(
        _ tweak: Tweak, _ plan: TweakPlan, _ action: TweakRecord.Action?, confirmed: Bool,
        history: TweakHistory, dryRun: Bool
    ) -> TweakChange {
        let outcome = applyCore(
            tweak, plan, action, confirmed: confirmed, history: history, dryRun: dryRun)
        logChange(
            outcome.change, verification: outcome.verification, action: action, dryRun: dryRun)
        return outcome.change
    }

    private static func logChange(
        _ change: TweakChange, verification: LogCode, action: TweakRecord.Action?, dryRun: Bool
    ) {
        let identifier = LogField.redacted(.tweakID, .tweakID)
        let recorded = LogField.flag(.recorded, change.recorded)
        let code = LogField.code(.verification, verification)
        switch (dryRun, action) {
        case (true, _):
            VerboseLog.event(.info, .tweaks, .tweakPreview, identifier, recorded, code)
        case (false, .rollback):
            VerboseLog.event(.info, .tweaks, .tweakRevert, identifier, recorded, code)
        default:
            VerboseLog.event(.info, .tweaks, .tweakApply, identifier, recorded, code)
        }
    }

    private static func applyCore(
        _ tweak: Tweak, _ plan: TweakPlan, _ action: TweakRecord.Action?, confirmed: Bool,
        history: TweakHistory, dryRun: Bool
    ) -> (change: TweakChange, verification: LogCode) {
        let before = read(tweak)
        // The DRY_RUN gate refuses the write and records nothing: it precedes every history
        // write, including the unsupported and unknown failures below.
        if dryRun {
            return (
                TweakChange(
                    record: TweakRecord(
                        tweakID: tweak.id, action: action ?? (plan.primary == nil ? .reset : .set),
                        before: before.current, after: nil, error: TweakError.gated.message),
                    reading: before),
                .verificationSkipped
            )
        }
        if case .probe = tweak.target {
            return (refused(tweak, before, .inspectionOnly, action), .verificationSkipped)
        }
        if case .unsupported(let reason) = before.state {
            return (failed(tweak, before, .unsupported(reason), action, history), .verificationSkipped)
        }
        if case .unknown(let reason) = before.state {
            return (
                failed(tweak, before, .unknownState(reason), action, history),
                .verificationSkipped
            )
        }
        if tweak.risk >= .medium, !confirmed {
            return (
                TweakChange(
                    record: TweakRecord(
                        tweakID: tweak.id, action: action ?? (plan.primary == nil ? .reset : .set),
                        before: before.current, after: nil,
                        error: TweakError.confirmationRequired("\(tweak.name) needs a confirmation before it changes.")
                            .message),
                    reading: before, needsConfirmation: true),
                .verificationSkipped
            )
        }

        let beforeCompanions = companionValues(tweak)
        let alreadyThere =
            matches(before.current, plan.primary)
            && zip(beforeCompanions, plan.companions).allSatisfy { matches($0.0, $0.1) }
        if alreadyThere {
            let record = TweakRecord(
                tweakID: tweak.id, action: action ?? (plan.primary == nil ? .reset : .set),
                before: before.current, after: before.current,
                beforeCompanions: beforeCompanions)
            return (
                TweakChange(record: record, reading: before, unchanged: true),
                .verificationSkipped
            )
        }

        do {
            try write(tweak.target, value: plan.primary)
            for (target, value) in zip(tweak.companions, plan.companions) {
                try write(target, value: value)
            }
        } catch let error as TweakError {
            restore(tweak, before: before.current, companions: beforeCompanions)
            return (failed(tweak, read(tweak), error, action, history), .verificationSkipped)
        } catch {
            restore(tweak, before: before.current, companions: beforeCompanions)
            return (
                failed(
                    tweak, read(tweak), .commandFailed(error.localizedDescription), action, history),
                .verificationSkipped
            )
        }

        let after = read(tweak)
        let afterCompanions = companionValues(tweak)
        let verified =
            after.isSupported && matches(after.current, plan.primary)
            && zip(afterCompanions, plan.companions).allSatisfy { matches($0.0, $0.1) }
        guard verified else {
            restore(tweak, before: before.current, companions: beforeCompanions)
            let restored = read(tweak)
            let detail =
                "Expected \(plan.primary?.display ?? "the system default") but read "
                + "\(after.current?.display ?? "nothing"). Restored the earlier value."
            return (
                failed(tweak, restored, .verificationFailed(detail), action, history),
                .verificationMismatch
            )
        }

        let record = TweakRecord(
            tweakID: tweak.id, action: action ?? (plan.primary == nil ? .reset : .set),
            before: before.current, after: after.current,
            beforeCompanions: beforeCompanions)
        history.append(record)
        return (TweakChange(record: record, reading: after, recorded: true), .verificationOk)
    }

    /// Removes the key, or clears the hidden flag for a file tweak, then verifies.
    public static func reset(
        _ tweak: Tweak, confirmed: Bool = false, history: TweakHistory = TweakHistory(),
        dryRun: Bool = DryRun.enabled
    ) -> TweakChange {
        switch tweak.target {
        case .defaults:
            return set(tweak, to: nil, confirmed: confirmed, history: history, dryRun: dryRun)
        case .fileHidden:
            return set(
                tweak, to: .boolean(false), confirmed: confirmed, history: history, dryRun: dryRun)
        case .probe:
            return refused(tweak, read(tweak), .inspectionOnly, .reset)
        }
    }

    /// Puts a recorded earlier state back, after checking that the record can belong to this
    /// tweak. A record whose value types do not match is refused, not applied.
    public static func rollback(
        _ record: TweakRecord, tweak: Tweak, history: TweakHistory = TweakHistory(),
        dryRun: Bool = DryRun.enabled
    ) -> TweakChange {
        let companions =
            record.beforeCompanions ?? Array(repeating: nil, count: tweak.companions.count)
        guard record.tweakID == tweak.id,
            typeMatches(record.before, tweak.target),
            companions.count == tweak.companions.count,
            zip(companions, tweak.companions).allSatisfy({ typeMatches($0.0, $0.1) })
        else {
            return refused(
                tweak, read(tweak),
                .verificationFailed("The record does not match this tweak. Nothing was restored."),
                .rollback)
        }
        VerboseLog.flush()
        return apply(
            tweak, TweakPlan(primary: record.before, companions: companions), .rollback,
            confirmed: true, history: history, dryRun: dryRun)
    }

    public static func rollback(
        _ record: TweakRecord, history: TweakHistory = TweakHistory(), dryRun: Bool = DryRun.enabled
    ) -> TweakChange? {
        guard let tweak = TweakCatalog.all.first(where: { $0.id == record.tweakID }) else { return nil }
        return rollback(record, tweak: tweak, history: history, dryRun: dryRun)
    }

    static func typeMatches(_ value: TweakValue?, _ target: TweakTarget) -> Bool {
        guard let value else { return true }
        switch target {
        case .defaults(_, _, let type): return value.type == type
        case .fileHidden: return value.type == .boolean
        case .probe: return false
        }
    }

    static func companionValues(_ tweak: Tweak) -> [TweakValue?] {
        tweak.companions.map { target in
            switch target {
            case .defaults(let domain, let key, let type):
                if case .success(let value) = readDefaults(domain: domain, key: key, type: type) {
                    return value
                }
                return nil
            case .fileHidden(let path):
                if case .success(let hidden) = readHidden(path) { return .boolean(hidden) }
                return nil
            case .probe:
                return nil
            }
        }
    }

    static func restore(_ tweak: Tweak, before: TweakValue?, companions: [TweakValue?]) {
        try? write(tweak.target, value: before)
        for (target, value) in zip(tweak.companions, companions) {
            try? write(target, value: value)
        }
    }

    /// Restarts the app that reads the changed preference. Returns false when there is
    /// nothing to restart or the process did not accept the signal.
    @discardableResult
    public static func restart(_ restart: TweakRestart, dryRun: Bool = DryRun.enabled) -> Bool {
        guard !dryRun, let process = restart.processName else { return false }
        return Subprocess.run(killallTool, [process], timeout: 10).ok
    }

    // MARK: Value mapping

    public static func state(for tweak: Tweak, current: TweakValue?) -> TweakState {
        let value = current ?? tweak.defaultValue
        switch tweak.control {
        case .toggle(let on, let off):
            if value == on { return .on }
            if off == nil, value == nil { return .off }
            if let off, value == off { return .off }
            if value == nil { return .off }
            return .custom(value?.display ?? "Unknown")
        case .choice(let options):
            guard let value else { return .custom("Not set") }
            if let match = options.first(where: { $0.value == value }) { return .value(match.label) }
            return .custom(value.display)
        case .folder:
            guard let value else { return .value("Desktop") }
            if case .string(let path) = value { return .value(abbreviate(path)) }
            return .custom(value.display)
        case .range(_, _, _, let unit):
            guard let value else { return .value("Not set") }
            return .value(unit.map { "\(value.display) \($0)" } ?? value.display)
        case .text:
            guard let value, case .string(let text) = value, !text.isEmpty else {
                return .value("Not set")
            }
            return .value(text)
        case .inspect:
            return .unknown("This is a read-only check.")
        }
    }

    static func abbreviate(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        guard path.hasPrefix(home) else { return path }
        return "~" + path.dropFirst(home.count)
    }

    static func matches(_ actual: TweakValue?, _ expected: TweakValue?) -> Bool {
        switch (actual, expected) {
        case (nil, nil): return true
        case (.number(let lhs)?, .number(let rhs)?): return abs(lhs - rhs) < 0.000_001
        case (let lhs?, let rhs?): return lhs == rhs
        case (_?, nil), (nil, _?): return false
        }
    }

    // MARK: Defaults

    struct ReadFailure: Error, LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    static func readDefaults(
        domain: String, key: String, type: TweakValueType
    ) -> Result<TweakValue?, ReadFailure> {
        let result = Subprocess.run(defaultsTool, ["read", domain, key])
        if result.ok {
            guard let value = parse(result.out, type: type) else {
                return .failure(ReadFailure(message: "Could not read \(key)."))
            }
            return .success(value)
        }
        let error = result.err.trimmingCharacters(in: .whitespacesAndNewlines)
        if isMissing(error) { return .success(nil) }
        return .failure(ReadFailure(message: error.isEmpty ? "Could not read \(key)." : error))
    }

    /// `defaults` reports an absent key or domain on stderr with one of these sentences.
    static func isMissing(_ message: String) -> Bool {
        message.localizedCaseInsensitiveContains("does not exist")
            || message.localizedCaseInsensitiveContains("could not find key")
            || message.localizedCaseInsensitiveContains("not found")
    }

    /// Pure parse of `defaults read` stdout. `type` comes from the catalog, so a value is
    /// never guessed from its shape.
    public static func parse(_ output: String, type: TweakValueType) -> TweakValue? {
        let text = output.trimmingCharacters(in: .whitespacesAndNewlines)
        switch type {
        case .boolean:
            switch text.lowercased() {
            case "1", "true", "yes": return .boolean(true)
            case "0", "false", "no": return .boolean(false)
            default: return nil
            }
        case .integer:
            return Int(text).map(TweakValue.integer)
        case .number:
            return Double(text).map(TweakValue.number)
        case .string:
            return .string(text)
        }
    }

    static func readHidden(_ path: String) -> Result<Bool, ReadFailure> {
        let result = Subprocess.run(statTool, ["-f", "%f", path])
        guard result.ok, let flags = UInt32(result.out.trimmingCharacters(in: .whitespacesAndNewlines))
        else {
            return .failure(ReadFailure(message: "Could not read the flag on \(path)."))
        }
        return .success(flags & 0x8000 != 0)
    }

    // MARK: Probes

    struct ProbeCommand {
        let tool: String
        let args: [String]
    }

    static func probeReading(_ tweak: Tweak, probe: TweakProbe) -> TweakReading {
        if probe == .automaticUpdates {
            switch readDefaults(
                domain: "com.apple.SoftwareUpdate", key: "AutomaticCheckEnabled", type: .boolean)
            {
            case .success(let value):
                let state: TweakState = value == .boolean(true) ? .on : .off
                return TweakReading(tweak: tweak, state: state, current: nil)
            case .failure(let error):
                return TweakReading(
                    tweak: tweak, state: .unknown(error.localizedDescription), current: nil)
            }
        }

        guard let command = probeCommand(probe) else {
            return TweakReading(
                tweak: tweak, state: .unknown("Nothing to read for this check."), current: nil)
        }
        let result = Subprocess.run(command.tool, command.args, timeout: 10)
        if !result.ok {
            if probe == .xcodeTools || probe == .homebrew {
                return TweakReading(tweak: tweak, state: .value("Not installed"), current: nil)
            }
            let message = result.message.isEmpty ? "The check did not run." : result.message
            return TweakReading(tweak: tweak, state: .unknown(message), current: nil)
        }
        guard let state = parseProbe(result.out, for: probe) else {
            return TweakReading(
                tweak: tweak, state: .unknown("The output was not recognised."), current: nil)
        }
        return TweakReading(tweak: tweak, state: state, current: nil)
    }

    static func probeCommand(_ probe: TweakProbe) -> ProbeCommand? {
        switch probe {
        case .firewall:
            ProbeCommand(
                tool: "/usr/libexec/ApplicationFirewall/socketfilterfw",
                args: ["--getglobalstate"])
        case .fileVault:
            ProbeCommand(tool: "/usr/bin/fdesetup", args: ["status"])
        case .gatekeeper:
            ProbeCommand(tool: "/usr/sbin/spctl", args: ["--status"])
        case .xcodeTools:
            ProbeCommand(tool: "/usr/bin/xcode-select", args: ["-p"])
        case .loginShell:
            ProbeCommand(
                tool: "/usr/bin/dscl",
                args: [".", "-read", "/Users/\(NSUserName())", "UserShell"])
        case .homebrew:
            ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
                .first { FileManager.default.isExecutableFile(atPath: $0) }
                .map { ProbeCommand(tool: $0, args: ["--version"]) }
        case .virtualization:
            ProbeCommand(tool: "/usr/sbin/sysctl", args: ["-n", "kern.hv_support"])
        case .automaticUpdates:
            nil
        }
    }

    /// Pure parse of a probe command's stdout, so the mapping is tested without the machine.
    public static func parseProbe(_ output: String, for probe: TweakProbe) -> TweakState? {
        let text = output.trimmingCharacters(in: .whitespacesAndNewlines)
        switch probe {
        case .firewall:
            if text.localizedCaseInsensitiveContains("enabled") { return .on }
            if text.localizedCaseInsensitiveContains("disabled") { return .off }
        case .fileVault:
            if text.contains("FileVault is On") { return .on }
            if text.contains("FileVault is Off") { return .off }
        case .gatekeeper:
            if text.localizedCaseInsensitiveContains("assessments enabled") { return .on }
            if text.localizedCaseInsensitiveContains("assessments disabled") { return .off }
        case .automaticUpdates:
            guard let value = parse(text, type: .boolean) else { return nil }
            return value == .boolean(true) ? .on : .off
        case .xcodeTools:
            return .value(text.isEmpty ? "Not installed" : text)
        case .loginShell:
            guard let range = text.range(of: "UserShell: ") else { return nil }
            return .value(String(text[range.upperBound...]))
        case .homebrew:
            guard let first = text.split(whereSeparator: \.isNewline).first else { return nil }
            return .value(String(first))
        case .virtualization:
            if text == "1" { return .value("Supported") }
            if text == "0" { return .value("Not supported") }
        }
        return nil
    }

    static func write(_ target: TweakTarget, value: TweakValue?) throws {
        switch target {
        case .defaults(let domain, let key, _):
            var args = ["write", domain, key]
            if let value {
                switch value {
                case .boolean(let flag): args += ["-bool", flag ? "true" : "false"]
                case .integer(let number): args += ["-int", "\(number)"]
                case .number(let number): args += ["-float", String(number)]
                case .string(let text): args += ["-string", text]
                }
            } else {
                args = ["delete", domain, key]
            }
            let result = Subprocess.run(defaultsTool, args)
            // Deleting an absent key reports an error but the requested state is already true.
            if !result.ok, !isMissing(result.err) {
                throw TweakError.commandFailed(result.message)
            }
        case .fileHidden(let path):
            let hidden = value == .boolean(true)
            let result = Subprocess.run(chflagsTool, [hidden ? "hidden" : "nohidden", path])
            guard result.ok else { throw TweakError.commandFailed(result.message) }
        case .probe:
            throw TweakError.inspectionOnly
        }
    }

    /// A refusal that is not a user-visible attempt: nothing was written and the ledger
    /// stays untouched.
    static func refused(
        _ tweak: Tweak, _ reading: TweakReading, _ error: TweakError,
        _ action: TweakRecord.Action?
    ) -> TweakChange {
        TweakChange(
            record: TweakRecord(
                tweakID: tweak.id, action: action ?? .set, before: reading.current, after: nil,
                error: error.message), reading: reading)
    }

    static func failed(
        _ tweak: Tweak, _ reading: TweakReading, _ error: TweakError,
        _ action: TweakRecord.Action?, _ history: TweakHistory
    ) -> TweakChange {
        let record = TweakRecord(
            tweakID: tweak.id, action: action ?? .set, before: reading.current, after: nil,
            error: error.message)
        history.append(record)
        return TweakChange(record: record, reading: reading, recorded: true)
    }
}

// MARK: - Catalog

/// The supported tweaks. Every entry maps to one preference key or one file flag, so a
/// change is a single write with a read-back check.
public enum TweakCatalog {
    static let global = "NSGlobalDomain"
    static let home = FileManager.default.homeDirectoryForCurrentUser

    public static let all: [Tweak] =
        finder + dock + keyboard + trackpad + screenshots + appearance + windows + security
        + developer

    // MARK: Finder

    private static let finder: [Tweak] = [
        Tweak(
            id: "finder.hidden-files",
            category: .finder,
            name: "Show hidden files",
            summary: "Display items that start with a dot, such as .gitignore.",
            detail:
                "Hidden items start with a dot. Their names are easy to change by accident, so Finder keeps them out of the way.",
            impact: "Finder windows",
            target: .defaults(domain: "com.apple.finder", key: "AppleShowAllFiles", type: .boolean),
            control: .toggle(on: .boolean(true), off: .boolean(false))),
        Tweak(
            id: "finder.extensions",
            category: .finder,
            name: "Show all filename extensions",
            summary: "Show the extension on every file name, not only on some.",
            detail:
                "A name like report.pdf shows its extension. Without it, two files named report look identical. The legacy com.apple.finder copy is not read, so a Mac that still writes it shows the NSGlobalDomain value.",
            impact: "Finder windows",
            target: .defaults(domain: global, key: "AppleShowAllExtensions", type: .boolean),
            control: .toggle(on: .boolean(true), off: .boolean(false))),
        Tweak(
            id: "finder.path-bar",
            category: .finder,
            name: "Show the path bar",
            summary: "Show the folder path at the bottom of every Finder window.",
            detail:
                "The path bar lists each folder from the disk down to the open one. You can drag a file onto any folder in it.",
            impact: "Finder windows",
            target: .defaults(domain: "com.apple.finder", key: "ShowPathbar", type: .boolean),
            control: .toggle(on: .boolean(true), off: .boolean(false)), restart: .finder),
        Tweak(
            id: "finder.status-bar",
            category: .finder,
            name: "Show the status bar",
            summary: "Show item count and free space at the bottom of Finder windows.",
            detail: "The status bar tells you how many items a folder holds and how much space is left.",
            impact: "Finder windows",
            target: .defaults(domain: "com.apple.finder", key: "ShowStatusBar", type: .boolean),
            control: .toggle(on: .boolean(true), off: .boolean(false)), restart: .finder),
        Tweak(
            id: "finder.folders-first",
            category: .finder,
            name: "Keep folders on top",
            summary: "Sort folders before files in Finder lists.",
            detail: "Folders stay together at the top when a list is sorted by name, date, or size.",
            impact: "Finder sorting",
            target: .defaults(domain: "com.apple.finder", key: "_FXSortFoldersFirst", type: .boolean),
            control: .toggle(on: .boolean(true), off: .boolean(false)), defaultValue: .boolean(true),
            restart: .finder),
        Tweak(
            id: "finder.search-current",
            category: .finder,
            name: "Search the current folder",
            summary: "Start a Finder search inside the folder you have open.",
            detail:
                "A search either covers the open folder or the whole Mac. Searching the open folder keeps unrelated results out.",
            impact: "Finder search",
            target: .defaults(domain: "com.apple.finder", key: "FXDefaultSearchScope", type: .string),
            control: .choice([
                TweakOption(label: "Current folder", value: .string("SCcf")),
                TweakOption(label: "This Mac", value: .string("SCev")),
                TweakOption(label: "Previous scope", value: .string("SCsp")),
            ]),
            defaultValue: .string("SCev")),
        Tweak(
            id: "finder.quit",
            category: .finder,
            name: "Add Quit Finder",
            summary: "Put Quit Finder in the Finder menu.",
            detail: "Finder stays open by design. This adds a Quit command, which you may want for a quiet screen.",
            impact: "Finder menu",
            target: .defaults(domain: "com.apple.finder", key: "QuitMenuItem", type: .boolean),
            control: .toggle(on: .boolean(true), off: .boolean(false))),
        Tweak(
            id: "finder.user-library",
            category: .finder,
            name: "Show the user Library folder",
            summary: "Make your Library folder visible in Finder.",
            detail:
                "The Library folder holds app settings and support files. macOS hides it so it is not deleted by mistake.",
            impact: "Finder",
            target: .fileHidden(path: home.appendingPathComponent("Library").path),
            control: .toggle(on: .boolean(false), off: .boolean(true)),
            defaultValue: .boolean(false)),
        Tweak(
            id: "finder.extension-warning",
            category: .finder,
            name: "Warn before changing an extension",
            summary: "Ask before a file's extension is changed.",
            detail:
                "Changing an extension can change which app opens a file. macOS asks first by default.",
            impact: "Finder",
            target: .defaults(
                domain: "com.apple.finder", key: "FXEnableExtensionChangeWarning", type: .boolean),
            control: .toggle(on: .boolean(true), off: .boolean(false)),
            defaultValue: .boolean(true), restart: .finder),
        Tweak(
            id: "finder.ds-store-network",
            category: .finder,
            name: "Keep .DS_Store off network folders",
            summary: "Do not write Finder metadata to shared network folders.",
            detail:
                "A .DS_Store file stores icon positions. On a network share it appears for everyone who opens the folder.",
            impact: "Network folders",
            target: .defaults(
                domain: "com.apple.desktopservices", key: "DSDontWriteNetworkStores", type: .boolean),
            control: .toggle(on: .boolean(true), off: .boolean(false)),
            defaultValue: .boolean(false)),
        Tweak(
            id: "finder.default-view",
            category: .finder,
            name: "Default folder view",
            summary: "Choose how a new Finder window shows its folder.",
            detail: "New windows open in this view until you choose another one for that folder.",
            impact: "Finder windows",
            target: .defaults(
                domain: "com.apple.finder", key: "FXPreferredViewStyle", type: .string),
            control: .choice([
                TweakOption(label: "Icon", value: .string("icnv")),
                TweakOption(label: "List", value: .string("Nlsv")),
                TweakOption(label: "Column", value: .string("clmv")),
                TweakOption(label: "Gallery", value: .string("glyv")),
            ]),
            defaultValue: .string("icnv"), restart: .finder),
    ]

    // MARK: Dock

    private static let dock: [Tweak] = [
        Tweak(
            id: "dock.autohide",
            category: .dock,
            name: "Automatically hide the Dock",
            summary: "Move the Dock out of the way until you point at its edge.",
            detail: "The Dock slides away and returns when the pointer reaches the screen edge.",
            impact: "Dock",
            target: .defaults(domain: "com.apple.dock", key: "autohide", type: .boolean),
            control: .toggle(on: .boolean(true), off: .boolean(false)), restart: .dock),
        Tweak(
            id: "dock.magnification",
            category: .dock,
            name: "Magnify Dock icons",
            summary: "Enlarge the icon under the pointer.",
            detail: "Magnification makes the Dock icon under the pointer larger than its neighbours.",
            impact: "Dock",
            target: .defaults(domain: "com.apple.dock", key: "magnification", type: .boolean),
            control: .toggle(on: .boolean(true), off: .boolean(false)), restart: .dock),
        Tweak(
            id: "dock.minimize-to-app",
            category: .dock,
            name: "Minimize into the app icon",
            summary: "Group a minimized window under its app instead of beside it.",
            detail: "The Dock holds one icon per app, so minimized windows do not add their own icons.",
            impact: "Dock",
            target: .defaults(
                domain: "com.apple.dock", key: "minimize-to-application", type: .boolean),
            control: .toggle(on: .boolean(true), off: .boolean(false)), restart: .dock),
        Tweak(
            id: "dock.recent-apps",
            category: .dock,
            name: "Show recent apps in the Dock",
            summary: "Keep recently used apps in a section beside the Trash.",
            detail: "Recent apps stay reachable without a search. Turn this off to keep the Dock fixed.",
            impact: "Dock",
            target: .defaults(domain: "com.apple.dock", key: "show-recents", type: .boolean),
            control: .toggle(on: .boolean(false), off: .boolean(true)), defaultValue: .boolean(true),
            restart: .dock),
        Tweak(
            id: "dock.mineffect",
            category: .dock,
            name: "Window minimize effect",
            summary: "Choose how a window moves into the Dock.",
            detail: "Genie stretches the window into the Dock. Scale shrinks it.",
            impact: "Dock animation",
            target: .defaults(domain: "com.apple.dock", key: "mineffect", type: .string),
            control: .choice([
                TweakOption(label: "Genie", value: .string("genie")),
                TweakOption(label: "Scale", value: .string("scale")),
            ]),
            defaultValue: .string("genie"), restart: .dock),
        Tweak(
            id: "dock.hidden-apps",
            category: .dock,
            name: "Show hidden apps in the Dock",
            summary: "Keep a hidden app in the Dock as a dimmed icon.",
            detail:
                "A hidden app keeps running. This leaves its icon visible so you can bring it back.",
            impact: "Dock",
            target: .defaults(domain: "com.apple.dock", key: "showhidden", type: .boolean),
            control: .toggle(on: .boolean(true), off: .boolean(false)),
            defaultValue: .boolean(false), restart: .dock),
        Tweak(
            id: "dock.autohide-speed",
            category: .dock,
            name: "Dock hide speed",
            summary: "Choose how fast the Dock slides away.",
            detail:
                "Lower values move the Dock faster. macOS uses about half a second until you change it.",
            impact: "Dock animation",
            target: .defaults(
                domain: "com.apple.dock", key: "autohide-time-modifier", type: .number),
            control: .range(min: 0.1, max: 2, step: 0.1, unit: "s"),
            defaultValue: .number(0.5), restart: .dock),
        Tweak(
            id: "dock.reveal-delay",
            category: .dock,
            name: "Dock reveal delay",
            summary: "Choose how long a hidden Dock waits before it appears.",
            detail:
                "Lower values reveal the Dock sooner. macOS uses about half a second until you change it.",
            impact: "Dock animation",
            target: .defaults(domain: "com.apple.dock", key: "autohide-delay", type: .number),
            control: .range(min: 0, max: 1.5, step: 0.1, unit: "s"),
            defaultValue: .number(0.5), restart: .dock),
    ]

    // MARK: Keyboard

    private static let keyboard: [Tweak] = [
        Tweak(
            id: "keyboard.repeat",
            category: .keyboard,
            name: "Repeat keys instead of showing accents",
            summary: "Holding a key types the character again instead of opening the accent menu.",
            detail:
                "By default, holding a letter opens a menu of accented forms. Turning this on makes the key repeat instead.",
            impact: "Text input in every app",
            target: .defaults(
                domain: global, key: "ApplePressAndHoldEnabled", type: .boolean),
            control: .toggle(on: .boolean(false), off: .boolean(true)),
            defaultValue: .boolean(true)),
        Tweak(
            id: "keyboard.full-access",
            category: .keyboard,
            name: "Tab through every control",
            summary: "Let Tab reach buttons, menus, and sliders, not only text fields and lists.",
            detail:
                "System Settings calls this Keyboard navigation. It changes how you move between controls in every app.",
            impact: "Keyboard navigation",
            target: .defaults(domain: global, key: "AppleKeyboardUIMode", type: .integer),
            control: .toggle(on: .integer(2), off: .integer(0)), defaultValue: .integer(0)),
        Tweak(
            id: "keyboard.smart-quotes",
            category: .keyboard,
            name: "Smart quotes",
            summary: "Turn straight quotes into typographic quotes as you type.",
            detail: "Smart quotes change a typed quote into a curly one. Code and paths expect straight quotes.",
            impact: "Text input in every app",
            target: .defaults(
                domain: global, key: "NSAutomaticQuoteSubstitutionEnabled", type: .boolean),
            control: .toggle(on: .boolean(true), off: .boolean(false)), defaultValue: .boolean(true)),
        Tweak(
            id: "keyboard.smart-dashes",
            category: .keyboard,
            name: "Smart dashes",
            summary: "Turn two hyphens into a dash as you type.",
            detail: "Smart dashes replace typed hyphens. Commands and code expect the characters you typed.",
            impact: "Text input in every app",
            target: .defaults(
                domain: global, key: "NSAutomaticDashSubstitutionEnabled", type: .boolean),
            control: .toggle(on: .boolean(true), off: .boolean(false)), defaultValue: .boolean(false)),
        Tweak(
            id: "keyboard.autocorrect",
            category: .keyboard,
            name: "Automatic spelling correction",
            summary: "Correct words while you type.",
            detail: "Autocorrection changes a word when macOS thinks it is misspelled.",
            impact: "Text input in every app",
            target: .defaults(
                domain: global, key: "NSAutomaticSpellingCorrectionEnabled", type: .boolean),
            control: .toggle(on: .boolean(true), off: .boolean(false)), defaultValue: .boolean(true)),
        Tweak(
            id: "keyboard.auto-capitalization",
            category: .keyboard,
            name: "Automatic capitalization",
            summary: "Start sentences with a capital letter.",
            detail: "macOS capitalizes the first letter after a sentence ends.",
            impact: "Text input in every app",
            target: .defaults(
                domain: global, key: "NSAutomaticCapitalizationEnabled", type: .boolean),
            control: .toggle(on: .boolean(true), off: .boolean(false)), defaultValue: .boolean(true)),
        Tweak(
            id: "keyboard.double-space-period",
            category: .keyboard,
            name: "Double space for a period",
            summary: "Turn two spaces into a period followed by a space.",
            detail: "Typing two spaces adds a period. Turn this off when you type two spaces on purpose.",
            impact: "Text input in every app",
            target: .defaults(
                domain: global, key: "NSAutomaticPeriodSubstitutionEnabled", type: .boolean),
            control: .toggle(on: .boolean(true), off: .boolean(false)), defaultValue: .boolean(true)),
        Tweak(
            id: "keyboard.text-completion",
            category: .keyboard,
            name: "Inline text completion",
            summary: "Offer a completion for the word you are typing.",
            detail: "A suggestion appears in line and Space accepts it.",
            impact: "Text input in every app",
            target: .defaults(
                domain: global, key: "NSAutomaticTextCompletionEnabled", type: .boolean),
            control: .toggle(on: .boolean(true), off: .boolean(false)), defaultValue: .boolean(false)),
        Tweak(
            id: "keyboard.repeat-rate",
            category: .keyboard,
            name: "Key repeat rate",
            summary: "Choose how fast a held key repeats.",
            detail: "Lower numbers repeat faster. 1 is fastest and 15 is slowest.",
            impact: "Text input in every app",
            target: .defaults(domain: global, key: "KeyRepeat", type: .integer),
            control: .range(min: 1, max: 15, step: 1, unit: nil),
            defaultValue: .integer(6)),
        Tweak(
            id: "keyboard.initial-delay",
            category: .keyboard,
            name: "Delay before keys repeat",
            summary: "Choose how long a key must be held before it repeats.",
            detail: "Lower numbers start repeating sooner. macOS uses 25 until you change it.",
            impact: "Text input in every app",
            target: .defaults(domain: global, key: "InitialKeyRepeat", type: .integer),
            control: .range(min: 10, max: 60, step: 5, unit: nil),
            defaultValue: .integer(25)),
    ]

    // MARK: Trackpad

    private static let trackpad: [Tweak] = [
        Tweak(
            id: "trackpad.tap-to-click",
            category: .trackpad,
            name: "Tap to click",
            summary: "Tap the trackpad once to click instead of pressing it.",
            detail: "A single tap acts as a click. Pressing the trackpad still works.",
            impact: "Trackpad",
            target: .defaults(
                domain: "com.apple.AppleMultitouchTrackpad", key: "Clicking", type: .boolean),
            control: .toggle(on: .boolean(true), off: .boolean(false)),
            companions: [
                .defaults(
                    domain: "com.apple.driver.AppleBluetoothMultitouch.trackpad", key: "Clicking",
                    type: .boolean)
            ],
            defaultValue: .boolean(false)),
        Tweak(
            id: "trackpad.three-finger-drag",
            category: .trackpad,
            name: "Three-finger drag",
            summary: "Drag an item with three fingers.",
            detail:
                "Dragging with three fingers moves the window or selection under the pointer. A one-finger drag then selects instead of moving.",
            impact: "Trackpad",
            target: .defaults(
                domain: "com.apple.AppleMultitouchTrackpad", key: "TrackpadThreeFingerDrag",
                type: .boolean),
            control: .toggle(on: .boolean(true), off: .boolean(false)),
            companions: [
                .defaults(
                    domain: "com.apple.driver.AppleBluetoothMultitouch.trackpad",
                    key: "TrackpadThreeFingerDrag", type: .boolean)
            ],
            defaultValue: .boolean(false)),
    ]

    // MARK: Screenshots

    private static let screenshots: [Tweak] = [
        Tweak(
            id: "screenshots.format",
            category: .screenshots,
            name: "Screenshot format",
            summary: "Choose the file type for new screenshots.",
            detail:
                "PNG keeps the image exact and is the largest. JPEG is smaller. TIFF is large and lossless. PDF suits documents.",
            impact: "New screenshots",
            target: .defaults(domain: "com.apple.screencapture", key: "type", type: .string),
            control: .choice([
                TweakOption(label: "PNG", value: .string("png")),
                TweakOption(label: "JPEG", value: .string("jpg")),
                TweakOption(label: "TIFF", value: .string("tiff")),
                TweakOption(label: "PDF", value: .string("pdf")),
            ]),
            defaultValue: .string("png")),
        Tweak(
            id: "screenshots.location",
            category: .screenshots,
            name: "Screenshot folder",
            summary: "Choose where new screenshots are saved.",
            detail: "New screenshots go to this folder. The Desktop is the macOS default.",
            impact: "New screenshots",
            target: .defaults(domain: "com.apple.screencapture", key: "location", type: .string),
            control: .folder,
            defaultValue: .string(home.appendingPathComponent("Desktop").path)),
        Tweak(
            id: "screenshots.shadow",
            category: .screenshots,
            name: "Include the window shadow",
            summary: "Keep the soft shadow around a captured window.",
            detail: "A window capture includes its shadow by default. Turning this off gives a clean edge.",
            impact: "New window captures",
            target: .defaults(domain: "com.apple.screencapture", key: "disable-shadow", type: .boolean),
            control: .toggle(on: .boolean(false), off: .boolean(true)), defaultValue: .boolean(false)),
        Tweak(
            id: "screenshots.thumbnail",
            category: .screenshots,
            name: "Show the floating thumbnail",
            summary: "Show the small preview after a capture.",
            detail: "The preview lets you mark up or share a capture before it settles into the folder.",
            impact: "New captures",
            target: .defaults(
                domain: "com.apple.screencapture", key: "show-thumbnail", type: .boolean),
            control: .toggle(on: .boolean(true), off: .boolean(false)), defaultValue: .boolean(true)),
        Tweak(
            id: "screenshots.filename",
            category: .screenshots,
            name: "Screenshot name",
            summary: "Set the name new screenshots start with.",
            detail:
                "A number is added after the name. Clearing it removes the key and uses the macOS default, Screenshot.",
            impact: "New screenshots",
            target: .defaults(domain: "com.apple.screencapture", key: "name", type: .string),
            control: .text(placeholder: "Screenshot"),
            defaultValue: .string("Screenshot")),
    ]

    // MARK: Appearance

    private static let appearance: [Tweak] = [
        Tweak(
            id: "appearance.dark",
            category: .appearance,
            name: "Dark appearance",
            summary: "Use the dark interface in apps that follow the system.",
            detail:
                "The system switches every window that follows the appearance. Apps that keep their own theme do not change.",
            impact: "Every app that follows the system",
            target: .defaults(domain: global, key: "AppleInterfaceStyle", type: .string),
            control: .toggle(on: .string("Dark"), off: nil)),
        Tweak(
            id: "appearance.reduce-motion",
            category: .appearance,
            name: "Reduce motion",
            summary: "Stop windows from sliding and zooming.",
            detail:
                "The system replaces some movement with a fade. Some apps pick up the change after you quit and open them again.",
            impact: "Interface motion",
            target: .defaults(
                domain: "com.apple.universalaccess", key: "reduceMotion", type: .boolean),
            control: .toggle(on: .boolean(true), off: .boolean(false))),
        Tweak(
            id: "appearance.reduce-transparency",
            category: .appearance,
            name: "Reduce transparency",
            summary: "Draw menus and sidebars as solid surfaces.",
            detail: "Transparency becomes a solid colour, which is easier to read over a busy desktop.",
            impact: "Menus and sidebars",
            target: .defaults(
                domain: "com.apple.universalaccess", key: "reduceTransparency", type: .boolean),
            control: .toggle(on: .boolean(true), off: .boolean(false))),
        Tweak(
            id: "appearance.increase-contrast",
            category: .appearance,
            name: "Increase contrast",
            summary: "Draw borders and separators more strongly.",
            detail: "Controls get a defined edge and lines get darker, which helps on a bright screen.",
            impact: "Interface contrast",
            target: .defaults(
                domain: "com.apple.universalaccess", key: "increaseContrast", type: .boolean),
            control: .toggle(on: .boolean(true), off: .boolean(false))),
        Tweak(
            id: "appearance.menu-bar-seconds",
            category: .appearance,
            name: "Show seconds in the clock",
            summary: "Add seconds to the menu bar clock.",
            detail: "The clock shows hours, minutes, and seconds. The menu bar needs a restart to redraw.",
            impact: "Menu bar clock",
            target: .defaults(
                domain: "com.apple.menuextra.clock", key: "ShowSeconds", type: .boolean),
            control: .toggle(on: .boolean(true), off: .boolean(false)), restart: .systemUI),
        Tweak(
            id: "appearance.autohide-menu-bar",
            category: .appearance,
            name: "Automatically hide the menu bar",
            summary: "Reveal the menu bar only when the pointer reaches the top edge.",
            detail:
                "The menu bar slides away, so every app menu needs a pointer trip to the top edge. It applies the next time you log in.",
            impact: "Menu bar",
            risk: .medium,
            target: .defaults(domain: global, key: "_HIHideMenuBar", type: .boolean),
            control: .toggle(on: .boolean(true), off: .boolean(false)), restart: .login),
    ]

    // MARK: Windows

    private static let windows: [Tweak] = [
        Tweak(
            id: "windows.reduce-animations",
            category: .windows,
            name: "Skip window animations",
            summary: "Open and close windows without the scale animation.",
            detail: "Windows appear and disappear at once instead of growing from the centre.",
            impact: "Window motion",
            target: .defaults(
                domain: global, key: "NSAutomaticWindowAnimationsEnabled", type: .boolean),
            control: .toggle(on: .boolean(false), off: .boolean(true)),
            defaultValue: .boolean(true)),
        Tweak(
            id: "windows.double-click",
            category: .windows,
            name: "Double-click the title bar",
            summary: "Choose what a double-click on a window title bar does.",
            detail: "The title bar either zooms the window, minimizes it, or does nothing.",
            impact: "Every window",
            target: .defaults(domain: global, key: "AppleActionOnDoubleClick", type: .string),
            control: .choice([
                TweakOption(label: "Zoom", value: .string("Maximize")),
                TweakOption(label: "Minimize", value: .string("Minimize")),
                TweakOption(label: "Do nothing", value: .string("None")),
            ]),
            defaultValue: .string("Maximize")),
        Tweak(
            id: "windows.document-tabs",
            category: .windows,
            name: "Open documents in tabs",
            summary: "Choose when an app opens documents in tabs instead of windows.",
            detail:
                "Automatic groups documents when a window is already open. Always groups them whenever the app supports tabs.",
            impact: "Document windows",
            target: .defaults(domain: global, key: "AppleWindowTabbingMode", type: .string),
            control: .choice([
                TweakOption(label: "Automatic", value: .string("automatic")),
                TweakOption(label: "Always", value: .string("always")),
                TweakOption(label: "Manually", value: .string("manual")),
            ]),
            defaultValue: .string("automatic")),
        Tweak(
            id: "windows.restore-state",
            category: .windows,
            name: "Reopen windows after quitting",
            summary: "Restore the windows an app had open when it quit.",
            detail:
                "The app reopens its last windows the next time you launch it. Turn this off to start with an empty window.",
            impact: "Every app",
            target: .defaults(domain: global, key: "NSQuitAlwaysKeepsWindows", type: .boolean),
            control: .toggle(on: .boolean(true), off: .boolean(false)),
            defaultValue: .boolean(true)),
        Tweak(
            id: "windows.stage-manager",
            category: .windows,
            name: "Stage Manager",
            summary: "Keep the front window centred and recent windows at the edge.",
            detail:
                "Stage Manager groups windows by task. The current window stays in the centre and other windows move to the side.",
            impact: "Window layout",
            target: .defaults(domain: "com.apple.WindowManager", key: "GloballyEnabled", type: .boolean),
            control: .toggle(on: .boolean(true), off: .boolean(false)), defaultValue: .boolean(false),
            minimumMajorVersion: 13),
    ]

    // MARK: Security

    private static let security: [Tweak] = [
        Tweak(
            id: "security.firewall",
            category: .security,
            name: "Application firewall",
            summary: "Check whether the firewall accepts incoming connections per app.",
            detail:
                "The application firewall blocks incoming connections for apps you have not allowed. It is off by default. Change it in Network settings.",
            impact: "Incoming connections",
            target: .probe(.firewall), control: .inspect),
        Tweak(
            id: "security.filevault",
            category: .security,
            name: "FileVault",
            summary: "Check whether the startup disk is encrypted.",
            detail:
                "FileVault encrypts the startup disk so its contents cannot be read without your password. Turn it on in Privacy and Security settings.",
            impact: "Disk encryption",
            target: .probe(.fileVault), control: .inspect),
        Tweak(
            id: "security.gatekeeper",
            category: .security,
            name: "Gatekeeper",
            summary: "Check whether downloaded apps must be verified before they run.",
            detail:
                "Gatekeeper checks the signature of an app the first time it opens. Chet never turns it off.",
            impact: "App launching",
            target: .probe(.gatekeeper), control: .inspect),
        Tweak(
            id: "security.automatic-updates",
            category: .security,
            name: "Automatic update checks",
            summary: "Check whether macOS looks for software updates on its own.",
            detail:
                "macOS checks for updates in the background when this is on. Install updates in Software Update settings.",
            impact: "Software updates",
            target: .probe(.automaticUpdates), control: .inspect),
    ]

    // MARK: Developer

    private static let developer: [Tweak] = [
        Tweak(
            id: "developer.xcode-tools",
            category: .developer,
            name: "Xcode command line tools",
            summary: "Show where the command line tools are installed.",
            detail:
                "Build tools such as clang and make come from this install. Install them with xcode-select --install.",
            impact: "Developer tools",
            target: .probe(.xcodeTools), control: .inspect),
        Tweak(
            id: "developer.login-shell",
            category: .developer,
            name: "Login shell",
            summary: "Show the shell a new terminal session starts.",
            detail: "Change it in Users and Groups settings, or with chsh.",
            impact: "Shell",
            target: .probe(.loginShell), control: .inspect),
        Tweak(
            id: "developer.homebrew",
            category: .developer,
            name: "Homebrew",
            summary: "Show the installed Homebrew version and prefix.",
            detail: "Homebrew installs packages under its prefix, /opt/homebrew on Apple Silicon.",
            impact: "Packages",
            target: .probe(.homebrew), control: .inspect),
        Tweak(
            id: "developer.virtualization",
            category: .developer,
            name: "Virtualization support",
            summary: "Check whether this Mac can run virtual machines.",
            detail:
                "The hypervisor framework needs hardware support. This Mac reports whether it is available.",
            impact: "Virtual machines",
            target: .probe(.virtualization), control: .inspect),
    ]
}

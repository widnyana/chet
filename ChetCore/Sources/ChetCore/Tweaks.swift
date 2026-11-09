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

// MARK: - Catalog model

public enum TweakCategory: String, CaseIterable, Sendable, Hashable {
    case finder
    case dock
    case keyboard
    case screenshots
    case appearance
    case windows

    public var title: String {
        switch self {
        case .finder: "Finder"
        case .dock: "Dock"
        case .keyboard: "Keyboard"
        case .screenshots: "Screenshots"
        case .appearance: "Appearance"
        case .windows: "Windows"
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

public enum TweakTarget: Sendable, Hashable {
    /// A key in a preferences domain, such as `com.apple.finder` and `ShowPathbar`.
    case defaults(domain: String, key: String, type: TweakValueType)
    /// The hidden user flag on a path, read with `stat` and written with `chflags`.
    case fileHidden(path: String)
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
    /// The value macOS ships with. Nil means the key is absent by default.
    public let defaultValue: TweakValue?
    public let minimumMajorVersion: Int?

    public init(
        id: String, category: TweakCategory, name: String, summary: String, detail: String,
        impact: String, risk: TweakRisk = .low, target: TweakTarget, control: TweakControl,
        defaultValue: TweakValue? = nil, restart: TweakRestart = .none,
        minimumMajorVersion: Int? = nil
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
        self.defaultValue = defaultValue
        self.minimumMajorVersion = minimumMajorVersion
    }

    /// The preferences domain and key, or the path, for the details sheet.
    public var configurationLabel: String {
        switch target {
        case .defaults(let domain, let key, _): "\(domain) · \(key)"
        case .fileHidden(let path): path
        }
    }
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
    public let error: String?

    public init(
        id: UUID = UUID(), tweakID: String, at: Date = Date(), action: Action,
        before: TweakValue?, after: TweakValue?, error: String? = nil
    ) {
        self.id = id
        self.tweakID = tweakID
        self.at = at
        self.action = action
        self.before = before
        self.after = after
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
}

extension TweakError {
    public var message: String {
        switch self {
        case .unsupported(let text): text
        case .unknownState(let text): text
        case .confirmationRequired(let text): text
        case .commandFailed(let text): text
        case .verificationFailed(let text): text
        case .gated: "Preview only. No tweak is changed."
        }
    }
}

public struct TweakChange: Sendable {
    public let record: TweakRecord
    public let reading: TweakReading
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
        tweaks.map(read)
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
        }
    }

    /// Writes one value, verifies it by reading it back, and records the change. A failed
    /// verification restores the value from before and records the failure.
    public static func set(
        _ tweak: Tweak, to value: TweakValue?, confirmed: Bool = false,
        history: TweakHistory = TweakHistory(), dryRun: Bool = DryRun.enabled
    ) -> TweakChange {
        apply(tweak, value, nil, confirmed: confirmed, history: history, dryRun: dryRun)
    }

    static func apply(
        _ tweak: Tweak, _ value: TweakValue?, _ action: TweakRecord.Action?, confirmed: Bool,
        history: TweakHistory, dryRun: Bool
    ) -> TweakChange {
        let before = read(tweak)
        if case .unsupported(let reason) = before.state {
            return failed(tweak, before, .unsupported(reason), action, history)
        }
        if case .unknown(let reason) = before.state {
            return failed(tweak, before, .unknownState(reason), action, history)
        }
        // The DRY_RUN gate refuses the write and records nothing: a preview must not leave a
        // change in the ledger that never happened.
        if dryRun {
            return TweakChange(
                record: TweakRecord(
                    tweakID: tweak.id, action: action ?? (value == nil ? .reset : .set),
                    before: before.current, after: nil, error: TweakError.gated.message),
                reading: before)
        }
        if tweak.risk >= .medium, !confirmed {
            return failed(
                tweak, before,
                .confirmationRequired("\(tweak.name) needs a confirmation before it changes."),
                action, history)
        }

        do {
            try write(tweak.target, value: value)
        } catch let error as TweakError {
            return failed(tweak, before, error, action, history)
        } catch {
            return failed(
                tweak, before, .commandFailed(error.localizedDescription), action, history)
        }

        let after = read(tweak)
        let verified = after.isSupported && matches(after.current, value)
        guard verified else {
            try? write(tweak.target, value: before.current)
            let restored = read(tweak)
            let detail =
                "Expected \(value?.display ?? "the system default") but read "
                + "\(after.current?.display ?? "nothing"). Restored the earlier value."
            return failed(tweak, restored, .verificationFailed(detail), action, history)
        }

        let record = TweakRecord(
            tweakID: tweak.id, action: action ?? (value == nil ? .reset : .set),
            before: before.current, after: after.current)
        history.append(record)
        return TweakChange(record: record, reading: after)
    }

    /// Removes the key, or clears the hidden flag for a file tweak, then verifies.
    public static func reset(
        _ tweak: Tweak, confirmed: Bool = false, history: TweakHistory = TweakHistory(),
        dryRun: Bool = DryRun.enabled
    ) -> TweakChange {
        let value: TweakValue?
        switch tweak.target {
        case .defaults: value = nil
        case .fileHidden: value = .boolean(false)
        }
        return set(tweak, to: value, confirmed: confirmed, history: history, dryRun: dryRun)
    }

    /// Puts a recorded earlier value back.
    public static func rollback(
        _ record: TweakRecord, history: TweakHistory = TweakHistory(), dryRun: Bool = DryRun.enabled
    ) -> TweakChange? {
        guard let tweak = TweakCatalog.all.first(where: { $0.id == record.tweakID }) else { return nil }
        return apply(
            tweak, record.before, .rollback, confirmed: true, history: history, dryRun: dryRun)
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
        }
    }

    static func failed(
        _ tweak: Tweak, _ reading: TweakReading, _ error: TweakError,
        _ action: TweakRecord.Action?, _ history: TweakHistory
    ) -> TweakChange {
        let record = TweakRecord(
            tweakID: tweak.id, action: action ?? .set, before: reading.current, after: nil,
            error: error.message)
        history.append(record)
        return TweakChange(record: record, reading: reading)
    }
}

// MARK: - Catalog

/// The supported tweaks. Every entry maps to one preference key or one file flag, so a
/// change is a single write with a read-back check.
public enum TweakCatalog {
    static let global = "NSGlobalDomain"
    static let home = FileManager.default.homeDirectoryForCurrentUser

    public static let all: [Tweak] = finder + dock + keyboard + screenshots + appearance + windows

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
                "A name like report.pdf shows its extension. Without it, two files named report look identical.",
            impact: "Finder windows",
            target: .defaults(domain: "com.apple.finder", key: "AppleShowAllExtensions", type: .boolean),
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
                TweakOption(label: "This Mac", value: .string("SCsp")),
            ]),
            defaultValue: .string("SCsp")),
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
            control: .toggle(on: .boolean(true), off: .boolean(false)), defaultValue: .boolean(false)),
        Tweak(
            id: "keyboard.text-completion",
            category: .keyboard,
            name: "Inline text completion",
            summary: "Offer a completion for the word you are typing.",
            detail: "A suggestion appears in line and Space accepts it.",
            impact: "Text input in every app",
            target: .defaults(
                domain: global, key: "NSAutomaticTextCompletionEnabled", type: .boolean),
            control: .toggle(on: .boolean(true), off: .boolean(false)), defaultValue: .boolean(true)),
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
            detail: "The menu bar slides away. It applies the next time you log in.",
            impact: "Menu bar",
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
}

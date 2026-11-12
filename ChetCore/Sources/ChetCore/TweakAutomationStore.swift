import Foundation

public enum AutomationStoreError: Error, Equatable, Sendable {
    case corrupt(URL)
    case writeFailed(String)
}

public struct AutomationLoad<Payload: Sendable>: Sendable {
    public let payload: Payload
    public let error: AutomationStoreError?

    public init(payload: Payload, error: AutomationStoreError?) {
        self.payload = payload
        self.error = error
    }
}

public struct WALState: Codable, Sendable, Equatable {
    public struct Applied: Codable, Sendable, Equatable {
        public var ruleID: UUID
        public var tweakID: String
        public var appliedValue: TweakValue?
        public var baseline: TweakValue?
        public var baselineSource: String
        public var phase: String
        public var appliedAt: Date
        public var conflict: String?

        public init(
            ruleID: UUID, tweakID: String, appliedValue: TweakValue?, baseline: TweakValue?,
            baselineSource: String, phase: String, appliedAt: Date, conflict: String?
        ) {
            self.ruleID = ruleID
            self.tweakID = tweakID
            self.appliedValue = appliedValue
            self.baseline = baseline
            self.baselineSource = baselineSource
            self.phase = phase
            self.appliedAt = appliedAt
            self.conflict = conflict
        }
    }

    public var applied: [String: Applied]

    public init(applied: [String: Applied] = [:]) {
        self.applied = applied
    }
}

public struct TriggerStore: Sendable {
    public static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Chet/tweak-automation-rules.json")
    }

    public let url: URL

    public init(url: URL = TriggerStore.defaultURL) {
        self.url = url
    }

    public func load() -> AutomationLoad<[TweakRule]> {
        AutomationFileIO.load(url: url, empty: [])
    }

    @discardableResult
    public func save(_ rules: [TweakRule]) -> AutomationStoreError? {
        AutomationFileIO.save(AutomationFile(payload: rules), url: url)
    }
}

public struct WALStore: Sendable {
    public static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Chet/tweak-automation-state.json")
    }

    public let url: URL

    public init(url: URL = WALStore.defaultURL) {
        self.url = url
    }

    public func load() -> AutomationLoad<WALState> {
        AutomationFileIO.load(url: url, empty: WALState())
    }

    @discardableResult
    public func save(_ state: WALState) -> AutomationStoreError? {
        AutomationFileIO.save(AutomationFile(payload: state), url: url)
    }
}

enum AutomationFileIO {
    static func load<Payload: Codable & Sendable>(
        url: URL, empty: Payload
    ) -> AutomationLoad<Payload> {
        guard let data = try? Data(contentsOf: url) else {
            return AutomationLoad(payload: empty, error: nil)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let file = try? decoder.decode(AutomationFile<Payload>.self, from: data),
            file.version == 1
        else {
            let corrupt = url.appendingPathExtension("corrupt")
            try? FileManager.default.removeItem(at: corrupt)
            try? data.write(to: corrupt)
            return AutomationLoad(payload: empty, error: .corrupt(url))
        }
        return AutomationLoad(payload: file.payload, error: nil)
    }

    static func save<Payload: Codable & Sendable>(
        _ file: AutomationFile<Payload>, url: URL
    ) -> AutomationStoreError? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(file) else {
            return .writeFailed("Could not encode the automation file.")
        }
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: url.path) {
                let backup = url.appendingPathExtension("bak")
                try? FileManager.default.removeItem(at: backup)
                try FileManager.default.moveItem(at: url, to: backup)
            }
            try data.write(to: url, options: .atomic)
            return nil
        } catch {
            return .writeFailed(error.localizedDescription)
        }
    }
}

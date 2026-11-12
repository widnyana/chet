import AppKit
import ChetCore
import Darwin
import Foundation

struct AXProbeOutput: Equatable, Sendable {
    let arguments: [String]
    let stdout: String
    let stderr: String
    let status: Int32
}

struct AXColorReport: Equatable {
    struct Sample: Equatable {
        let hex: String
        let share: Double
    }

    let label: String
    let frame: CGRect?
    let point: CGPoint?
    let background: String
    let backgroundShare: Double?
    let ink: String?
    let inkShare: Double?
    let contrast: Double?
    let peak: String?
    let peakShare: Double?
    let peakContrast: Double?
    let palette: [Sample]
}

enum AXProbeError: Error, LocalizedError, CustomStringConvertible, Equatable {
    case missingEnvironment(String)
    case unreadablePID(String)
    case invalidPID(String)
    case processNotRunning(pid_t)
    case wrongBundleIdentifier(pid: pid_t, expected: String, actual: String)
    case missingBinary(String)
    case captureFileFailure(String)
    case launchFailed(path: String, detail: String)
    case commandFailed(AXProbeOutput)
    case malformedFrame(String)
    case malformedColor(String)

    var errorDescription: String? { description }

    var description: String {
        switch self {
        case .missingEnvironment(let name):
            return "\(name) is not set"
        case .unreadablePID(let path):
            return "could not read \(path)"
        case .invalidPID(let text):
            return "app.pid does not contain a process id: \(text)"
        case .processNotRunning(let pid):
            return "chet pid \(pid) is not running"
        case .wrongBundleIdentifier(let pid, let expected, let actual):
            return "pid \(pid) is \(actual), not \(expected)"
        case .missingBinary(let path):
            return "axdrv is not executable at \(path); set CHET_AXDRV"
        case .captureFileFailure(let path):
            return "could not create the axdrv output capture at \(path)"
        case .launchFailed(let path, let detail):
            return "could not launch \(path): \(detail)"
        case .commandFailed(let output):
            let detail = output.stderr.isEmpty ? output.stdout : output.stderr
            return "axdrv exited with status \(output.status): \(output.arguments.joined(separator: " "))\n\(detail)"
        case .malformedFrame(let text):
            return "could not parse axdrv frame output: \(text)"
        case .malformedColor(let text):
            return "could not parse axdrv color output: \(text)"
        }
    }
}

struct AXProbe {
    static let bundleIdentifier = "id.web.widnyana.chet"

    let root: URL
    let binary: URL
    let pid: pid_t

    init(root: URL, binary: URL? = nil, environment: [String: String] = ProcessInfo.processInfo.environment)
        throws
    {
        let root = root.standardizedFileURL
        let pid = try Self.readPID(root: root)
        try Self.verify(pid: pid, expectedBundle: Self.bundleIdentifier)
        let binary = try Self.resolveBinary(binary, environment: environment)
        self.root = root
        self.binary = binary
        self.pid = pid
    }

    init(environment: [String: String] = ProcessInfo.processInfo.environment) throws {
        guard let raw = environment["CHET_UITEST_ROOT"], !raw.isEmpty else {
            throw AXProbeError.missingEnvironment("CHET_UITEST_ROOT")
        }
        try self.init(
            root: URL(fileURLWithPath: raw, isDirectory: true), environment: environment)
    }

    @discardableResult
    func dump(_ selector: AXSelector = AXSelector([])) throws -> AXProbeOutput {
        try run("dump", selector)
    }

    func texts(_ selector: AXSelector = AXSelector([])) throws -> [String] {
        let output = try run("texts", selector)
        return output.stdout.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
    }

    func frame(_ selector: AXSelector) throws -> CGRect {
        let output = try run("frame", selector)
        return try Self.parseFrame(output.stdout)
    }

    func color(_ selector: AXSelector) throws -> AXColorReport {
        let output = try run("color", selector)
        return try Self.parseColor(output.stdout)
    }

    @discardableResult
    func select(_ selector: AXSelector) throws -> AXProbeOutput {
        try run("select", selector)
    }

    @discardableResult
    func press(_ selector: AXSelector) throws -> AXProbeOutput {
        try run("press", selector)
    }

    @discardableResult
    func click(_ selector: AXSelector) throws -> AXProbeOutput {
        try run("click", selector)
    }

    private func run(_ command: String, _ selector: AXSelector) throws -> AXProbeOutput {
        try execute(["--pid", String(pid), command] + Self.operands(selector))
    }

    private func execute(_ arguments: [String]) throws -> AXProbeOutput {
        let process = Process()
        process.executableURL = binary
        process.arguments = arguments

        let stem = "axprobe-\(getpid())-\(UUID().uuidString)"
        let directory = FileManager.default.temporaryDirectory
        let stdoutURL = directory.appendingPathComponent("\(stem).out")
        let stderrURL = directory.appendingPathComponent("\(stem).err")
        guard FileManager.default.createFile(atPath: stdoutURL.path, contents: nil),
            FileManager.default.createFile(atPath: stderrURL.path, contents: nil)
        else {
            try? FileManager.default.removeItem(at: stdoutURL)
            try? FileManager.default.removeItem(at: stderrURL)
            throw AXProbeError.captureFileFailure(directory.path)
        }
        guard let stdoutHandle = try? FileHandle(forWritingTo: stdoutURL),
            let stderrHandle = try? FileHandle(forWritingTo: stderrURL)
        else {
            try? FileManager.default.removeItem(at: stdoutURL)
            try? FileManager.default.removeItem(at: stderrURL)
            throw AXProbeError.captureFileFailure(stdoutURL.path)
        }
        defer {
            try? stdoutHandle.close()
            try? stderrHandle.close()
            try? FileManager.default.removeItem(at: stdoutURL)
            try? FileManager.default.removeItem(at: stderrURL)
        }

        process.standardOutput = stdoutHandle
        process.standardError = stderrHandle
        do {
            try process.run()
        } catch {
            throw AXProbeError.launchFailed(path: binary.path, detail: error.localizedDescription)
        }
        process.waitUntilExit()
        try? stdoutHandle.close()
        try? stderrHandle.close()

        let stdout = Self.text(from: try? Data(contentsOf: stdoutURL))
        let stderr = Self.text(from: try? Data(contentsOf: stderrURL))
        let output = AXProbeOutput(
            arguments: [binary.path] + arguments,
            stdout: stdout,
            stderr: stderr,
            status: process.terminationStatus)
        guard output.status == 0 else {
            throw AXProbeError.commandFailed(output)
        }
        return output
    }

    static func parseFrame(_ text: String) throws -> CGRect {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "x", with: ",")
        let parts = cleaned.split(whereSeparator: { $0 == "," || $0.isWhitespace }).compactMap {
            Double($0)
        }
        guard parts.count == 4 else {
            throw AXProbeError.malformedFrame(text)
        }
        return CGRect(x: parts[0], y: parts[1], width: parts[2], height: parts[3])
    }

    static func parseColor(_ text: String) throws -> AXColorReport {
        var label = ""
        var frame: CGRect?
        var point: CGPoint?
        var background: String?
        var backgroundShare: Double?
        var ink: String?
        var inkShare: Double?
        var contrast: Double?
        var peak: String?
        var peakShare: Double?
        var peakContrast: Double?
        var palette: [AXColorReport.Sample] = []

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            let fields = line.split(whereSeparator: \.isWhitespace).map(String.init)
            guard let key = fields.first else { continue }
            switch key {
            case "label":
                label = fields.dropFirst().joined(separator: " ")
            case "frame":
                frame = try parseFrame(fields.dropFirst().joined(separator: " "))
            case "background":
                background = try colorValue(fields, at: 1, line: line)
                backgroundShare = try shareValue(fields, at: 2, line: line)
            case "ink":
                let value = try colorValue(fields, at: 1, line: line)
                ink = value == "none" ? nil : value
                inkShare = try shareValue(fields, at: 2, line: line)
                contrast = try contrastValue(fields, at: 4, line: line)
            case "peak":
                let value = try colorValue(fields, at: 1, line: line)
                peak = value == "none" ? nil : value
                peakShare = try shareValue(fields, at: 2, line: line)
                peakContrast = try contrastValue(fields, at: 4, line: line)
            case "colors":
                palette = try paletteValues(Array(fields.dropFirst()), line: line)
            default:
                if fields.count == 2, let sample = try? pointSample(fields) {
                    point = sample.point
                    background = sample.color
                    backgroundShare = 1
                }
            }
        }

        if let background {
            return AXColorReport(
                label: label,
                frame: frame,
                point: point,
                background: background,
                backgroundShare: backgroundShare,
                ink: ink,
                inkShare: inkShare,
                contrast: contrast,
                peak: peak,
                peakShare: peakShare,
                peakContrast: peakContrast,
                palette: palette)
        }
        throw AXProbeError.malformedColor(text)
    }

    private static func resolveBinary(_ explicit: URL?, environment: [String: String]) throws -> URL {
        let candidate: URL
        if let explicit {
            candidate = explicit.standardizedFileURL
        } else if let raw = environment["CHET_AXDRV"], !raw.isEmpty {
            candidate = fileURL(raw)
        } else if let discovered = searchAncestors(from: Bundle.main.bundleURL) {
            candidate = discovered
        } else {
            candidate =
                URL(
                    fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true
                ).appendingPathComponent(".build/tools/axdrv").standardizedFileURL
        }
        guard FileManager.default.isExecutableFile(atPath: candidate.path) else {
            throw AXProbeError.missingBinary(candidate.path)
        }
        return candidate
    }

    private static func searchAncestors(from bundle: URL) -> URL? {
        var directory = bundle.deletingLastPathComponent()
        for _ in 0..<8 {
            let candidate = directory.appendingPathComponent(".build/tools/axdrv")
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
            let parent = directory.deletingLastPathComponent()
            if parent.path == directory.path { break }
            directory = parent
        }
        return nil
    }

    private static func fileURL(_ path: String) -> URL {
        let expanded = (path as NSString).expandingTildeInPath
        if expanded.hasPrefix("/") {
            return URL(fileURLWithPath: expanded).standardizedFileURL
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            .appendingPathComponent(expanded).standardizedFileURL
    }

    private static func readPID(root: URL) throws -> pid_t {
        let url = root.appendingPathComponent("app.pid")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            throw AXProbeError.unreadablePID(url.path)
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let pid = pid_t(trimmed), pid > 0 else {
            throw AXProbeError.invalidPID(trimmed)
        }
        return pid
    }

    private static func verify(pid: pid_t, expectedBundle: String) throws {
        if kill(pid, 0) != 0 && errno != EPERM {
            throw AXProbeError.processNotRunning(pid)
        }
        guard let application = NSRunningApplication(processIdentifier: pid) else {
            throw AXProbeError.processNotRunning(pid)
        }
        let actual = application.bundleIdentifier ?? "unknown"
        guard actual == expectedBundle else {
            throw AXProbeError.wrongBundleIdentifier(pid: pid, expected: expectedBundle, actual: actual)
        }
    }

    private static func operands(_ selector: AXSelector) -> [String] {
        selector.terms.map { term in
            guard let key = term.key else { return term.value }
            if key == .contains { return term.value }
            if key == .description { return "desc=\(term.value)" }
            return "\(key.rawValue)=\(term.value)"
        }
    }

    private static func text(from data: Data?) -> String {
        guard let data else { return "" }
        return String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
    }

    private static func pointSample(_ fields: [String]) throws -> (point: CGPoint, color: String) {
        guard fields.count == 2 else {
            throw AXProbeError.malformedColor(fields.joined(separator: " "))
        }
        let coordinates = fields[0].split(separator: ",").compactMap { Double($0) }
        guard coordinates.count == 2, fields[1] == "none" || isHex(fields[1]) else {
            throw AXProbeError.malformedColor(fields.joined(separator: " "))
        }
        return (CGPoint(x: coordinates[0], y: coordinates[1]), fields[1])
    }

    private static func colorValue(_ fields: [String], at index: Int, line: String) throws -> String {
        guard fields.count > index else {
            throw AXProbeError.malformedColor(line)
        }
        let value = fields[index]
        guard value == "none" || isHex(value) else {
            throw AXProbeError.malformedColor(line)
        }
        return value
    }

    private static func shareValue(_ fields: [String], at index: Int, line: String) throws -> Double {
        guard fields.count > index else {
            throw AXProbeError.malformedColor(line)
        }
        return try share(fields[index], line: line)
    }

    private static func share(_ token: String, line: String) throws -> Double {
        let digits = token.hasSuffix("%") ? String(token.dropLast()) : token
        guard let value = Double(digits) else {
            throw AXProbeError.malformedColor(line)
        }
        return value / 100
    }

    private static func contrastValue(_ fields: [String], at index: Int, line: String) throws -> Double {
        guard fields.count > index, fields[index - 1] == "contrast" else {
            throw AXProbeError.malformedColor(line)
        }
        let digits = String(fields[index].split(separator: ":").first ?? "")
        guard let value = Double(digits) else {
            throw AXProbeError.malformedColor(line)
        }
        return value
    }

    private static func paletteValues(_ fields: [String], line: String) throws -> [AXColorReport.Sample] {
        guard fields.count % 2 == 0 else {
            throw AXProbeError.malformedColor(line)
        }
        var samples: [AXColorReport.Sample] = []
        for index in stride(from: 0, to: fields.count, by: 2) {
            let color = fields[index]
            guard color == "none" || isHex(color) else {
                throw AXProbeError.malformedColor(line)
            }
            samples.append(
                AXColorReport.Sample(
                    hex: color,
                    share: try share(fields[index + 1], line: line)))
        }
        return samples
    }

    private static func isHex(_ value: String) -> Bool {
        guard value.hasPrefix("#") else { return false }
        let digits = value.dropFirst()
        return digits.count == 6 && digits.allSatisfy(\.isHexDigit)
    }
}

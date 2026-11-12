import AppKit
import ChetCore
import Foundation

@MainActor
final class TweakAutomationController {
    private let ruleStore: TriggerStore
    private let stateStore: WALStore
    private let engine: TweakAutomationEngine
    private let dryRun: Bool
    private var rules: [TweakRule] = []
    private var state = WALState()
    private var kvoToken: NSKeyValueObservation?
    private var notificationTokens: [NSObjectProtocol] = []
    private var terminateDebounce: Task<Void, Never>?
    private(set) var lastError: String?

    init(ruleStore: TriggerStore, stateStore: WALStore, engine: TweakAutomationEngine, dryRun: Bool) {
        self.ruleStore = ruleStore
        self.stateStore = stateStore
        self.engine = engine
        self.dryRun = dryRun
    }

    var ruleCount: Int { rules.count }
    var currentRules: [TweakRule] { rules }

    func start() {
        let loadedRules = ruleStore.load()
        if let error = loadedRules.error { lastError = describe(error) }
        rules = loadedRules.payload
        let loadedState = stateStore.load()
        if let error = loadedState.error { lastError = describe(error) }
        state = loadedState.payload
        observe()
        Task { await reconcile() }
    }

    func stop() {
        kvoToken?.invalidate()
        kvoToken = nil
        for token in notificationTokens {
            NSWorkspace.shared.notificationCenter.removeObserver(token)
        }
        notificationTokens = []
        terminateDebounce?.cancel()
        terminateDebounce = nil
    }

    func reconcile() async {
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        let executor = AutomationExecutor(rules: rules, state: state, engine: engine, dryRun: dryRun)
        let result = await executor.reconcile(running: running)
        state = result.state
        if !dryRun, let error = stateStore.save(state) { lastError = describe(error) }
        log(result.decisions)
    }

    func setRule(_ rule: TweakRule) async throws {
        if let applied = state.applied[rule.tweakID] {
            let outcome = await engine.revert(tweakID: rule.tweakID, to: applied.baseline)
            if case .failed(let message) = outcome { throw AutomationEditError(message) }
            state.applied.removeValue(forKey: rule.tweakID)
        }
        if let index = rules.firstIndex(where: { $0.id == rule.id }) {
            rules[index] = rule
        } else {
            rules.append(rule)
        }
        if let error = ruleStore.save(rules) { throw AutomationEditError(describe(error)) }
        await reconcile()
    }

    func deleteRule(_ id: UUID) async throws {
        guard let rule = rules.first(where: { $0.id == id }) else { return }
        if let applied = state.applied[rule.tweakID] {
            let outcome = await engine.revert(tweakID: rule.tweakID, to: applied.baseline)
            if case .failed(let message) = outcome { throw AutomationEditError(message) }
            state.applied.removeValue(forKey: rule.tweakID)
        }
        rules.removeAll { $0.id == id }
        if let error = ruleStore.save(rules) { throw AutomationEditError(describe(error)) }
        await reconcile()
    }

    func revertAll() async {
        for (tweakID, applied) in state.applied {
            let outcome = await engine.revert(tweakID: tweakID, to: applied.baseline)
            if case .failed = outcome { continue }
            state.applied.removeValue(forKey: tweakID)
        }
        if !dryRun { _ = stateStore.save(state) }
    }

    private func observe() {
        kvoToken = NSWorkspace.shared.observe(\.runningApplications, options: [.new]) {
            [weak self] _, _ in
            Task { @MainActor in await self?.reconcile() }
        }
        let center = NSWorkspace.shared.notificationCenter
        let names: [Notification.Name] = [
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didWakeNotification,
            NSWorkspace.willPowerOffNotification,
            NSWorkspace.sessionDidResignActiveNotification,
            NSWorkspace.sessionDidBecomeActiveNotification,
        ]
        for name in names {
            notificationTokens.append(
                center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    Task { @MainActor in await self?.reconcile() }
                })
        }
        notificationTokens.append(
            center.addObserver(
                forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.terminateDebounce?.cancel()
                    self?.terminateDebounce = Task {
                        try? await Task.sleep(for: .seconds(1.5))
                        await self?.reconcile()
                    }
                }
            })
        notificationTokens.append(
            NotificationCenter.default.addObserver(
                forName: NSApplication.willTerminateNotification, object: nil, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.stop() }
            })
    }

    private func log(_ decisions: [AutomationDecision]) {
        if dryRun {
            VerboseLog.event(
                .info, .tweaks, .tweakPreview, .code(.outcome, .outcomeOk),
                .count(.items, decisions.count))
            return
        }
        for decision in decisions {
            switch decision {
            case .apply:
                VerboseLog.event(
                    .info, .tweaks, .tweakAutomationApplied,
                    .redacted(.tweakID, .tweakID), .redacted(.bundleID, .bundleID))
            case .revert:
                VerboseLog.event(
                    .info, .tweaks, .tweakAutomationReverted, .redacted(.tweakID, .tweakID))
            case .conflict:
                VerboseLog.event(
                    .warn, .tweaks, .tweakAutomationConflict, .redacted(.tweakID, .tweakID))
            case .orphan:
                VerboseLog.event(
                    .warn, .tweaks, .tweakAutomationOrphaned, .redacted(.tweakID, .tweakID))
            case .keep:
                break
            }
        }
    }

    private func describe(_ error: AutomationStoreError) -> String {
        switch error {
        case .corrupt(let url):
            "The automation file at \(url.lastPathComponent) could not be read."
        case .writeFailed(let message):
            message
        }
    }
}

struct AutomationEditError: Error, LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? { message }
}

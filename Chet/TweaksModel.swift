import ChetCore
import Foundation
import Observation

/// What the Tweaks list is allowed to show.
enum TweakFilter: String, CaseIterable, Identifiable {
    case all
    case changed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All"
        case .changed: "Changed"
        }
    }
}

/// A change that waits for the user to confirm it.
struct PendingChange: Identifiable {
    let tweak: Tweak
    let value: TweakValue?
    var id: String { tweak.id }
}

/// Reads the catalog on a background task, applies one tweak at a time, and keeps the
/// recorded history. Every write goes through `TweakEngine`, which verifies by reading back.
@MainActor
@Observable
final class TweaksModel {
    private(set) var readings: [TweakReading] = []
    private(set) var history: [TweakRecord] = []
    private(set) var isLoading = true
    private(set) var busy: Set<String> = []
    /// Restart target -> tweaks whose change waits on it. A restart notice belongs to the
    /// row that was changed, not to every row that shares the target.
    private(set) var pendingRestarts: [TweakRestart: Set<String>] = [:]

    var query = ""
    var filter: TweakFilter = .all
    /// The last failure, shown above the list until dismissed.
    var errorMessage: String?
    /// The last restart that failed, shown with the error.
    var restartFailure: TweakRestart?
    /// A medium or high risk change that the sheet is asking about.
    var pendingConfirmation: PendingChange?
    /// Per-row failure text. A failed change leaves the previous state in place and the
    /// reason here, until the next successful change or a dismiss.
    private(set) var failures: [String: String] = [:]

    private let historyStore = TweakHistory()
    private let catalog = TweakCatalog.all
    /// DRY_RUN: the catalog is still read, so states stay truthful, but every control is
    /// disabled and the model refuses a write before it reaches the engine.
    let isGated = DryRun.enabled

    // MARK: Queries

    func reading(for id: String) -> TweakReading? {
        readings.first { $0.id == id }
    }

    func lastChange(for id: String) -> TweakRecord? {
        history.last { $0.tweakID == id && $0.error == nil }
    }

    func needsRestart(_ id: String) -> Bool {
        pendingRestarts.values.contains { $0.contains(id) }
    }

    /// Targets that still have a waiting change, in catalog restart order.
    var pendingRestartTargets: [TweakRestart] {
        TweakRestart.allCases.filter { pendingRestarts[$0]?.isEmpty == false }
    }

    var customizedCount: Int {
        readings.filter { $0.isCustomized && $0.isSupported }.count
    }

    var historyURL: URL { historyStore.url }

    /// The last recorded value before a change, when a rollback is possible.
    func rollbackTarget(for id: String) -> TweakRecord? {
        guard let last = lastChange(for: id), !busy.contains(id) else { return nil }
        return last
    }

    func tweaks(in category: TweakCategory) -> [TweakReading] {
        readings.filter { $0.tweak.category == category && matches($0) }
    }

    var matchingCategories: [TweakCategory] {
        TweakCategory.allCases.filter { !tweaks(in: $0).isEmpty }
    }

    var hasAnyMatch: Bool { !matchingCategories.isEmpty }

    private func matches(_ reading: TweakReading) -> Bool {
        switch filter {
        case .all: break
        case .changed: guard reading.isCustomized else { return false }
        }
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !text.isEmpty else { return true }
        return reading.tweak.name.lowercased().contains(text)
            || reading.tweak.summary.lowercased().contains(text)
            || reading.tweak.category.title.lowercased().contains(text)
    }

    // MARK: Loading

    func load() async {
        let catalog = catalog
        let loaded = await Task.detached(priority: .userInitiated) {
            TweakEngine.readAll(catalog)
        }.value
        let store = historyStore
        readings = loaded
        history = await Task.detached { store.load() }.value
        isLoading = false
        #if DEBUG
            applyPreviewIfRequested()
        #endif
    }

    func reload() async {
        isLoading = readings.isEmpty
        await load()
    }

    /// Read once for a surface that only shows counts, such as Settings.
    func ensureLoaded() async {
        guard readings.isEmpty else { return }
        await load()
    }

    // MARK: Changes

    func set(_ tweak: Tweak, to value: TweakValue?) {
        guard !isGated else { return refuse() }
        guard !busy.contains(tweak.id) else { return }
        busy.insert(tweak.id)
        let store = historyStore
        Task {
            let change = await Task.detached(priority: .userInitiated) {
                TweakEngine.set(tweak, to: value, history: store)
            }.value
            finish(change, tweak: tweak, requested: value)
        }
    }

    /// Flips a toggle to the other declared value, or back to the default when "off" is
    /// the absent key.
    func toggle(_ tweak: Tweak) {
        set(tweak, to: nextValue(for: tweak))
    }

    private func nextValue(for tweak: Tweak) -> TweakValue? {
        let isOn = reading(for: tweak.id)?.state == .on
        if case .toggle(let on, let off) = tweak.control {
            return isOn ? off : on
        }
        return isOn ? nil : tweak.defaultValue
    }

    func reset(_ tweak: Tweak) {
        guard !isGated else { return refuse() }
        guard !busy.contains(tweak.id) else { return }
        busy.insert(tweak.id)
        let store = historyStore
        Task {
            let change = await Task.detached(priority: .userInitiated) {
                TweakEngine.reset(tweak, history: store)
            }.value
            finish(change, tweak: tweak, requested: nil)
        }
    }

    /// The sheet confirmed a medium or high risk change.
    func confirmPendingChange() {
        guard let pending = pendingConfirmation else { return }
        pendingConfirmation = nil
        guard !isGated else { return refuse() }
        guard !busy.contains(pending.tweak.id) else { return }
        busy.insert(pending.tweak.id)
        let store = historyStore
        Task {
            let change = await Task.detached(priority: .userInitiated) {
                TweakEngine.set(
                    pending.tweak, to: pending.value, confirmed: true, history: store)
            }.value
            finish(change, tweak: pending.tweak, requested: pending.value)
        }
    }

    func cancelPendingChange() {
        pendingConfirmation = nil
    }

    func rollback(_ record: TweakRecord, tweak: Tweak) {
        guard !isGated else { return refuse() }
        guard !busy.contains(tweak.id) else { return }
        busy.insert(tweak.id)
        let store = historyStore
        Task {
            let change = await Task.detached(priority: .userInitiated) {
                TweakEngine.rollback(record, tweak: tweak, history: store)
            }.value
            finish(change, tweak: tweak, requested: record.before)
        }
    }

    func restart(_ target: TweakRestart) {
        guard !isGated else { return refuse() }
        guard target != .none else { return }
        Task {
            let ok = await Task.detached { TweakEngine.restart(target) }.value
            if ok {
                pendingRestarts[target] = nil
            } else {
                restartFailure = target
                errorMessage = "Could not restart \(TweakCopy.processName(target))."
            }
        }
    }

    /// Puts every changed tweak back to its macOS default and returns how many changed.
    @discardableResult
    func resetEverything() async -> Int {
        guard !isGated else {
            refuse()
            return 0
        }
        let targets = readings.filter { $0.isCustomized && $0.isSupported }.map(\.tweak)
        guard !targets.isEmpty else { return 0 }
        let store = historyStore
        let changes = await Task.detached(priority: .userInitiated) {
            targets.map { TweakEngine.reset($0, confirmed: true, history: store) }
        }.value
        var failuresCount = 0
        for change in changes {
            if let index = readings.firstIndex(where: { $0.id == change.record.tweakID }) {
                readings[index] = change.reading
            }
            if change.recorded { history.append(change.record) }
            if let error = change.record.error {
                failures[change.record.tweakID] = error
                failuresCount += 1
            } else {
                failures[change.record.tweakID] = nil
            }
        }
        if failuresCount > 0 {
            errorMessage = "\(failuresCount) tweaks could not be reset."
        }
        return targets.count - failuresCount
    }

    func failure(for id: String) -> String? { failures[id] }

    func dismissError() {
        errorMessage = nil
        restartFailure = nil
    }

    private func refuse() {
        errorMessage = TweakError.gated.message
    }

    #if DEBUG
        /// Renders a write-path surface under DRY_RUN without writing anything. Debug builds
        /// only; release builds do not contain this function.
        private func applyPreviewIfRequested() {
            guard ProcessInfo.processInfo.environment["CHET_TWEAK_PREVIEW"] == "confirm" else {
                return
            }
            guard let tweak = catalog.first(where: { $0.risk >= .medium }) else { return }
            pendingConfirmation = PendingChange(tweak: tweak, value: nextValue(for: tweak))
        }
    #endif

    private func finish(_ change: TweakChange, tweak: Tweak, requested: TweakValue?) {
        busy.remove(tweak.id)
        if change.needsConfirmation {
            pendingConfirmation = PendingChange(tweak: tweak, value: requested)
            return
        }
        if let index = readings.firstIndex(where: { $0.id == tweak.id }) {
            readings[index] = change.reading
        }
        if change.recorded { history.append(change.record) }
        if change.unchanged {
            failures[tweak.id] = nil
            return
        }
        if let error = change.record.error {
            failures[tweak.id] = error
            errorMessage = "\(tweak.name): \(error)"
            return
        }
        failures[tweak.id] = nil
        if tweak.restart != .none {
            pendingRestarts[tweak.restart, default: []].insert(tweak.id)
        }
    }
}

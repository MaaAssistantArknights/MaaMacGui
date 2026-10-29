import Foundation

/// Only owns a pending scheduling intent. DailyRunCoordinator remains the sole
/// owner of the actual run, stop, and post-hook lifecycle.
@MainActor final class ScheduleHandoff<Snapshot> {
    enum Occupancy: Equatable { case idle, daily(UUID), tool }
    enum StartResult { case started(UUID?), skipped, failed }
    struct Terminal { let id: UUID; let cleanupSucceeded: Bool }

    var occupancy: @MainActor () -> Occupancy
    var terminal: @MainActor () -> Terminal?
    var canStop: @MainActor (UUID) -> Bool
    var canForce: @MainActor (Snapshot) -> Bool
    var stop: @MainActor (UUID) async throws -> Void
    var start: @MainActor (Snapshot, Bool, @escaping @MainActor () -> Bool) async -> StartResult
    var isCurrent: @MainActor (ScheduleOccurrence) -> Bool
    var report: @MainActor (ScheduleOccurrence, ScheduleOccurrence.Result, String, UUID?) -> Void
    private(set) var pending: ScheduleOccurrence?
    private var work: Task<Void, Never>?
    private var deadline: Task<Void, Never>?
    private let timeout: Duration

    init(timeout: Duration = .seconds(30), occupancy: @escaping @MainActor () -> Occupancy,
         terminal: @escaping @MainActor () -> Terminal?, canStop: @escaping @MainActor (UUID) -> Bool,
         canForce: @escaping @MainActor (Snapshot) -> Bool = { _ in true },
         stop: @escaping @MainActor (UUID) async throws -> Void,
         start: @escaping @MainActor (Snapshot, Bool, @escaping @MainActor () -> Bool) async -> StartResult,
         isCurrent: @escaping @MainActor (ScheduleOccurrence) -> Bool,
         report: @escaping @MainActor (ScheduleOccurrence, ScheduleOccurrence.Result, String, UUID?) -> Void) {
        self.timeout = timeout
        self.occupancy = occupancy
        self.terminal = terminal
        self.canStop = canStop
        self.canForce = canForce
        self.stop = stop
        self.start = start
        self.isCurrent = isCurrent
        self.report = report
    }

    func submit(_ occurrence: ScheduleOccurrence, force: Bool, snapshot: Snapshot) {
        guard pending == nil else {
            report(occurrence, .skipped, "anotherSchedulePending", nil)
            return
        }
        let initial = occupancy()
        guard initial != .tool else {
            report(occurrence, .skipped, "utilityTaskBusy", nil)
            return
        }
        if initial != .idle, !force {
            report(occurrence, .skipped, "dailyTaskBusy", nil)
            return
        }
        if case .daily = initial, force, !canForce(snapshot) {
            report(occurrence, .skipped, "forceRecoveryUnavailable", nil)
            return
        }
        pending = occurrence
        if case .daily = initial {
            deadline = Task { [weak self, timeout] in
                do { try await Task.sleep(for: timeout) } catch { return }
                self?.finish(occurrence, result: .failed, detail: "handoffTimedOut")
            }
        }
        work = Task { [weak self] in
            guard let self else { return }
            if case .daily(let previousID) = initial {
                while current(occurrence), occupancy() != .idle {
                    guard canForce(snapshot) else {
                        finish(occurrence, result: .cancelled, detail: "forceRecoveryUnavailable")
                        return
                    }
                    guard occupancy() == .daily(previousID) else {
                        finish(occurrence, result: .cancelled, detail: "runChanged")
                        return
                    }
                    if canStop(previousID) {
                        do { try await stop(previousID) }
                        catch {
                            finish(occurrence, result: .failed, detail: "stopFailed")
                            return
                        }
                        break
                    }
                    do { try await Task.sleep(for: .milliseconds(50)) } catch { return }
                }
                while current(occurrence), occupancy() != .idle {
                    guard canForce(snapshot) else {
                        finish(occurrence, result: .cancelled, detail: "forceRecoveryUnavailable")
                        return
                    }
                    guard occupancy() == .daily(previousID) else {
                        finish(occurrence, result: .cancelled, detail: "runChanged")
                        return
                    }
                    do { try await Task.sleep(for: .milliseconds(50)) } catch { return }
                }
                guard current(occurrence) else { return }
                guard canForce(snapshot) else {
                    finish(occurrence, result: .cancelled, detail: "forceRecoveryUnavailable")
                    return
                }
                guard let end = terminal(), end.id == previousID, end.cleanupSucceeded else {
                    finish(occurrence, result: .cancelled, detail: "cleanupFailed")
                    return
                }
            }
            guard current(occurrence) else { return }
            deadline?.cancel()
            // The run coordinator reserves its run before its first await. The
            // snapshot was captured at the occurrence, before a possible stop.
            guard Date() <= occurrence.expiresAt else {
                finish(occurrence, result: .missed, detail: "handoffExpired")
                return
            }
            let result = await start(snapshot, initial != .idle, { [weak self] in self?.current(occurrence) == true && self?.canForce(snapshot) == true })
            guard pending?.id == occurrence.id else { return }
            switch result {
            case .started(let id): finish(occurrence, result: .started, runID: id)
            case .skipped: finish(occurrence, result: .skipped, detail: "admissionRejected")
            case .failed: finish(occurrence, result: .failed, detail: "startFailed")
            }
        }
    }

    func cancelPending(detail: String = "userCancelled") {
        guard let occurrence = pending else { return }
        finish(occurrence, result: .cancelled, detail: detail)
    }

    func invalidateIfNeeded() {
        if let pending, !isCurrent(pending) { cancelPending(detail: "scheduleChanged") }
    }

    private func current(_ occurrence: ScheduleOccurrence) -> Bool {
        guard pending?.id == occurrence.id, !Task.isCancelled else { return false }
        guard isCurrent(occurrence) else {
            finish(occurrence, result: .cancelled, detail: "scheduleChanged")
            return false
        }
        return true
    }

    private func finish(_ occurrence: ScheduleOccurrence, result: ScheduleOccurrence.Result,
                        detail: String = "", runID: UUID? = nil) {
        guard pending?.id == occurrence.id else { return }
        pending = nil
        deadline?.cancel()
        deadline = nil
        work?.cancel()
        work = nil
        report(occurrence, result, detail, runID)
    }
}

/// State for a single isolated Core recovery task. Core nested ProcessTask
/// callbacks can have taskid 0, so the chain start marker scopes these events.
struct ForcedGameRecovery {
    let taskID: Int32
    let chain: String
    let requiresHome: Bool
    var started = false
    var lastWasHome = false
    var completed = false
    var allCompleted = false
    var failed = false

    mutating func chainStart(_ id: Int32) { if id == taskID { started = true } }
    mutating func subtask(chain: String, taskID id: Int32, name: String, algorithm: String) {
        guard started, !completed, chain == self.chain, id == 0 || id == taskID else { return }
        // Both resource tasks are MatchTemplate checks for the home menu.
        lastWasHome = ["Home", "StartUp"].contains(name) && algorithm == "MatchTemplate"
    }
    mutating func chainFinish(_ id: Int32, success: Bool) {
        guard started, id == taskID else { return }
        completed = true
        if !success { failed = true }
    }
    mutating func allFinished(_ ids: [Int32]) { if ids.contains(taskID) { allCompleted = true } }
    var verified: Bool { started && completed && allCompleted && (!requiresHome || lastWasHome) && !failed }
}

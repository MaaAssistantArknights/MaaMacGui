import AppKit
import Combine
import Foundation

@MainActor final class TaskTimerManager: ObservableObject {
    static let shared = TaskTimerManager()

    @Published private(set) var recentOccurrences: [ScheduleOccurrence] = []
    @Published private(set) var failure: String?
    private weak var viewModel: MAAViewModel?
    private var plans: [DailyTaskSchedule] = []
    private var pulse: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var triggerGrace: TimeInterval = 60
    private var sleepDisabled = false
    var sleepAssertionID: IOPMAssertionID = 0
    private var store = ScheduleOccurrenceStore(directory: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!.appendingPathComponent("Schedule"))

    private struct ScheduleSnapshot {
        let daily: DailyRunSnapshot
        let recoveryEligible: @MainActor () -> Bool
    }

    private var handoff: ScheduleHandoff<ScheduleSnapshot>?

    private func makeHandoff() -> ScheduleHandoff<ScheduleSnapshot> {
        ScheduleHandoff<ScheduleSnapshot>(
        timeout: .seconds(30),
        occupancy: { [weak self] in
            guard let model = self?.viewModel else { return .tool }
            if let run = model.dailyRunCoordinator.active { return .daily(run.id) }
            return model.canStartTasks ? .idle : .tool
        },
        terminal: { [weak self] in
            guard let end = self?.viewModel?.dailyRunCoordinator.lastTerminal else { return nil }
            return .init(id: end.id, cleanupSucceeded: end.cleanupSucceeded == true)
        },
        canStop: { [weak self] expectedID in
            guard let model = self?.viewModel, let run = model.dailyRunCoordinator.active,
                  run.id == expectedID else { return false }
            return !model.isStartStopInFlight && run.status != .postHook && run.status != .stopping
        },
        canForce: { $0.recoveryEligible() },
        stop: { [weak self] expectedID in
            guard let model = self?.viewModel else { throw CancellationError() }
            guard model.dailyRunCoordinator.active?.id == expectedID else { throw CancellationError() }
            try await model.stop(cancelScheduledStart: false)
        },
        start: { [weak self] snapshot, needsRecovery, isCurrent in
            guard let model = self?.viewModel else { return .failed }
            let result = await model.startDailyTasks(origin: .schedule, snapshot: snapshot.daily, recoverGame: needsRecovery, recoveryCurrent: isCurrent)
            switch result {
            case .started:
                let id = model.dailyRunCoordinator.active?.id ?? model.dailyRunCoordinator.lastTerminal?.id
                return .started(id)
            case .skipped: return .skipped
            case .failed: return .failed
            }
        },
        isCurrent: { [weak self] occurrence in
            self?.plans.contains(where: { $0.id == occurrence.planID && $0.isEnabled && $0.revision == occurrence.revision }) == true
        },
        report: { [weak self] occurrence, result, detail, runID in
            self?.record(occurrence, result: result, detail: detail, runID: runID)
        })
    }

    private init() {}

    func configureSharedDirectory(_ directory: URL) throws {
        guard viewModel == nil else { throw BackgroundScheduleError.helperUnavailable }
        let shared = ScheduleOccurrenceStore(directory: directory)
        try shared.mergeHistory(from: store)
        store = shared
    }

    func setBackgroundSchedulingEnabled(_ enabled: Bool) {
        triggerGrace = enabled ? 300 : 60
    }

    func acceptBackgroundIntent(_ intent: BackgroundScheduleIntent) throws {
        guard let viewModel, handoff != nil,
              let plan = plans.first(where: { $0.id == intent.occurrence.planID && $0.isEnabled && $0.revision == intent.occurrence.revision })
        else { throw BackgroundScheduleError.invalidIntent }
        guard try store.acceptBackgroundIntent(intent.occurrence) else { return }
        let daily = DailyRunSnapshot(profileID: intent.profileID, tasks: viewModel.tasks)
        let snapshot = ScheduleSnapshot(daily: daily, recoveryEligible: viewModel.forceRecoveryEligibility(snapshot: daily))
        handoff?.submit(intent.occurrence, force: plan.forceStart, snapshot: snapshot)
        reloadRecords()
    }

    func expireBackgroundIntents() throws {
        // Reload the recent-occurrence view only when the ledger actually
        // changed; otherwise this stays a wasted full-ledger transaction.
        if try store.expireUndeliveredBackgroundIntents() { reloadRecords() }
    }

    func rejectBackgroundIntent(_ occurrence: ScheduleOccurrence, detail: String) throws {
        try store.rejectBackgroundIntent(occurrence.id, result: Date() > occurrence.expiresAt ? .missed : .cancelled, detail: detail)
        reloadRecords()
    }

    func connectToModel(viewModel: MAAViewModel) {
        guard self.viewModel !== viewModel else { return }
        pulse?.invalidate()
        cancellables.removeAll()
        self.viewModel = viewModel
        handoff = makeHandoff()
        do { try store.recoverInterrupted(); reloadRecords() }
        catch { reportFailure(error) }
        viewModel.$scheduledDailyTaskTimers.sink { [weak self] value in
            guard let self else { return }
            plans = value
            handoff?.invalidateIfNeeded()
            scheduleNextCheck()
        }.store(in: &cancellables)
        NotificationCenter.default.publisher(for: .MAAPreventSystemSleepingChanged)
            .sink { [weak self] in self?.preventSystemFromSleepingIfNeeded($0.object as? Bool ?? false) }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: .MAACancelPendingScheduledStart)
            .sink { [weak self] _ in self?.handoff?.cancelPending() }.store(in: &cancellables)
        NotificationCenter.default.publisher(for: .MAADailyRunFinished)
            .sink { [weak self] note in
                guard let end = note.object as? RunContext else { return }
                self?.recordTerminal(end)
            }.store(in: &cancellables)
        for name in [Notification.Name.NSSystemTimeZoneDidChange, .NSCalendarDayChanged, .NSSystemClockDidChange] {
            NotificationCenter.default.publisher(for: name).sink { [weak self] _ in
                self?.refreshRunningTimersIfNecessary()
            }.store(in: &cancellables)
        }
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)
            .sink { [weak self] _ in self?.refreshRunningTimersIfNecessary() }.store(in: &cancellables)
        preventSystemFromSleepingIfNeeded(viewModel.preventSystemSleeping)
        checkDueSchedules()
    }

    func refreshRunningTimersIfNecessary() { checkDueSchedules() }
    func cancelPendingStart() { handoff?.cancelPending() }

    private func scheduleNextCheck() {
        pulse?.invalidate()
        let now = Date()
        let calendar = Calendar.autoupdatingCurrent
        let next = plans.filter(\.isEnabled).compactMap { ScheduleCalendar.nextDate(for: $0, after: now, calendar: calendar) }.min()
        let delay = min(15, max(0.1, next?.timeIntervalSince(now) ?? 15))
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.checkDueSchedules() }
        }
        RunLoop.main.add(timer, forMode: .common)
        pulse = timer
    }

    private func checkDueSchedules() {
        defer { scheduleNextCheck() }
        guard let viewModel, viewModel.isCoreInitialized else { return }
        do {
            if let candidate = try BackgroundScheduleCheck.claimDue(plans: plans, now: .now,
                    calendar: .autoupdatingCurrent, grace: triggerGrace, ledger: store, source: "") {
                let daily = DailyRunSnapshot(profileID: viewModel.dailyTaskProfile, tasks: viewModel.tasks)
                let snapshot = ScheduleSnapshot(daily: daily, recoveryEligible: viewModel.forceRecoveryEligibility(snapshot: daily))
                handoff?.submit(candidate.1, force: candidate.0.forceStart, snapshot: snapshot)
            }
            reloadRecords()
            if let end = viewModel.dailyRunCoordinator.lastTerminal { recordTerminal(end) }
        } catch { reportFailure(error) }
    }

    private func record(_ occurrence: ScheduleOccurrence, result: ScheduleOccurrence.Result,
                        detail: String, runID: UUID? = nil) {
        do {
            try store.update(occurrence.id, result: result, detail: detail, runID: runID)
            reloadRecords()
            print("Schedule \(occurrence.id) \(result.rawValue) \(detail) runID=\(runID?.uuidString ?? "none")")
            if result == .started, let end = viewModel?.dailyRunCoordinator.lastTerminal, end.id == runID { recordTerminal(end) }
        } catch { reportFailure(error) }
    }

    private func recordTerminal(_ end: RunContext) {
        guard let occurrence = recentOccurrences.first(where: { $0.runID == end.id && $0.result == .started }) else { return }
        let result: ScheduleOccurrence.Result
        // cleanupSucceeded == nil means the outcome is unknown (journal degraded
        // abandon path or boot-interrupted recovery), not a failed cleanup; only
        // a definitive false mislabels the run so the user-visible record keeps
        // the honest outcome instead of turning a user cancel into "cleanupFailed".
        if end.cleanupSucceeded == false {
            result = .failed
        } else {
            switch end.outcome {
            case .completed: result = .completed
            case .cancelled: result = .cancelled
            case .failed: result = .failed
            default: result = .interrupted
            }
        }
        record(occurrence, result: result, detail: end.cleanupSucceeded == false ? "cleanupFailed" : "", runID: end.id)
    }

    private func reloadRecords() {
        do { recentOccurrences = Array(try store.records().prefix(20)); failure = nil }
        catch { reportFailure(error) }
    }

    private func reportFailure(_ error: Error) {
        failure = String(localized: "定时记录无法读取或保存，已停止本次触发。")
        print("Schedule ledger: \(error)")
    }

    private func preventSystemFromSleepingIfNeeded(_ needed: Bool) {
        if needed {
            sleepDisabled = IOPMAssertionCreateWithName(kIOPMAssertionTypeNoIdleSleep as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn), "Daily task timer need to be run all the time" as CFString, &sleepAssertionID) == kIOReturnSuccess
            print("Disable screen sleep: \(sleepDisabled ? "successful" : "failed")")
        } else if sleepDisabled {
            // Enable screen sleep again
            IOPMAssertionRelease(sleepAssertionID)
            sleepDisabled = false
            print("Enabled screen sleep")
        }
    }
}

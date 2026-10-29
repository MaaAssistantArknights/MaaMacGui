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
    private var lastDay: Date?
    private var sleepDisabled = false
    var sleepAssertionID: IOPMAssertionID = 0
    private var store = ScheduleOccurrenceStore(directory: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!.appendingPathComponent("Schedule"))

    private var handoff: ScheduleHandoff<DailyRunSnapshot>?

    private func makeHandoff() -> ScheduleHandoff<DailyRunSnapshot> {
        ScheduleHandoff<DailyRunSnapshot>(
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
        stop: { [weak self] in
            guard let model = self?.viewModel else { throw CancellationError() }
            // Preparation and cleanup are owned by the coordinator. A stop
            // rejected during admission can be retried until its bounded deadline.
            while model.isStartStopInFlight {
                try await Task.sleep(for: .milliseconds(50))
                try Task.checkCancellation()
            }
            if let phase = model.dailyRunCoordinator.active?.status,
               phase != .postHook && phase != .stopping {
                try await model.stop(cancelScheduledStart: false)
            }
        },
        start: { [weak self] snapshot in
            guard let model = self?.viewModel else { return .failed }
            let result = await model.startDailyTasks(origin: .schedule, snapshot: snapshot)
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
        NotificationCenter.default.publisher(for: Notification.Name("MAACancelPendingScheduledStart"))
            .sink { [weak self] _ in self?.handoff?.cancelPending() }.store(in: &cancellables)
        NotificationCenter.default.publisher(for: Notification.Name("MAADailyRunFinished"))
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
        guard let viewModel else { return }
        let now = Date()
        let calendar = Calendar.autoupdatingCurrent
        let today = calendar.startOfDay(for: now)
        var days = [today]
        if let lastDay, lastDay < today,
           let yesterday = calendar.date(byAdding: .day, value: -1, to: today) { days.insert(yesterday, at: 0) }
        lastDay = today
        var due: [(DailyTaskSchedule, ScheduleOccurrence)] = []
        for day in days {
            for plan in plans.filter({ $0.isEnabled && $0.isValid }) {
                guard let occurrence = ScheduleCalendar.occurrence(for: plan, on: day, calendar: calendar) else { continue }
                let missingTimeDue = occurrence.result == .missed && (day < today || {
                    let current = calendar.dateComponents([.hour, .minute], from: now)
                    return (current.hour ?? 0) * 60 + (current.minute ?? 0) >= plan.hour * 60 + plan.minute
                }())
                guard occurrence.scheduledAt <= now || missingTimeDue else { continue }
                if occurrence.result == .missed || now >= occurrence.expiresAt {
                    do {
                        if try store.claim(occurrence) {
                            record(occurrence, result: .missed, detail: occurrence.result == .missed ? "nonexistentLocalTime" : "triggerExpired")
                        }
                    } catch { reportFailure(error); return }
                } else {
                    due.append((plan, occurrence))
                }
            }
        }
        due.sort { left, right in
            left.1.scheduledAt == right.1.scheduledAt ? left.0.id.uuidString < right.0.id.uuidString : left.1.scheduledAt < right.1.scheduledAt
        }
        let snapshot = DailyRunSnapshot(profileID: viewModel.dailyTaskProfile, tasks: viewModel.tasks)
        // Choose the stable winner before claiming. A second process that
        // sees the winner already claimed must not promote the next plan.
        for (index, item) in due.enumerated() {
            do {
                guard try store.claim(item.1) else { continue }
                if index == 0 { handoff?.submit(item.1, force: item.0.forceStart, snapshot: snapshot) }
                else { record(item.1, result: .skipped, detail: "simultaneousSchedule") }
            } catch { reportFailure(error); return }
        }
        reloadRecords()
        if let end = viewModel.dailyRunCoordinator.lastTerminal { recordTerminal(end) }
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
        if end.cleanupSucceeded != true {
            result = .failed
        } else {
            switch end.outcome {
            case .completed: result = .completed
            case .cancelled: result = .cancelled
            case .failed: result = .failed
            default: result = .interrupted
            }
        }
        record(occurrence, result: result, detail: end.cleanupSucceeded == true ? "" : "cleanupFailed", runID: end.id)
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

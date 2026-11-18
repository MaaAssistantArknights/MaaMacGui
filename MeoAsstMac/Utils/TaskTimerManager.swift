import AppKit
import Combine
import Foundation
import IOKit.pwr_mgt

@MainActor final class TaskTimerManager {
    static let shared = TaskTimerManager()

    struct RunningTimer {
        let config: MAAViewModel.DailyTaskTimer
        let timer: Timer
    }

    private var viewModel: MAAViewModel?
    private var runningTimers: [String: RunningTimer] = [:]

    private static let maxConnectionAttempts = 3
    private static let retryDelaySeconds = 60
    private var pendingRetry: (timerKey: String, task: Task<Void, Never>)?

    private func cancelPendingRetry() {
        pendingRetry?.task.cancel()
        pendingRetry = nil
    }

    private var sleepDisabled = false
    var sleepAssertionID: IOPMAssertionID = 0

    private var cancellables = Set<AnyCancellable>()

    private init() {}

    func connectToModel(viewModel: MAAViewModel) {
        self.viewModel = viewModel

        viewModel.$status
            .filter { $0 != .idle }
            .sink { [weak self] _ in self?.cancelPendingRetry() }
            .store(in: &cancellables)

        viewModel.$scheduledDailyTaskTimers
            .sink { [weak self] in
                self?.updateRunningTimers(timerConfigs: $0)
            }
            .store(in: &cancellables)

        NotificationCenter.default
            .publisher(for: .MAAPreventSystemSleepingChanged)
            .sink { [weak self] in
                self?.preventSystemFromSleepingIfNeeded($0.object as? Bool ?? false)
            }
            .store(in: &cancellables)

        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.screensDidWakeNotification)
            .sink { [weak self] _ in
                print("System wakes up, try to refresh timer")
                self?.refreshRunningTimersIfNecessary()
            }
            .store(in: &cancellables)
        // Call it manually for the first time
        preventSystemFromSleepingIfNeeded(viewModel.preventSystemSleeping)

        print("TaskTimerManager connected")
    }

    func refreshRunningTimersIfNecessary() {
        guard let viewModel else {
            print("Skip refreshing daily task timer, due to missing viewModel.")
            return
        }
        let isDailyTaskRunning = viewModel.status != .idle
        guard !isDailyTaskRunning else {
            print("Skip refreshing daily task timer, due to running daily task.")
            return
        }

        print("Refresing Daily Tasks Timers")
        for (key, runningTimer) in runningTimers {
            runningTimer.stop()
            runningTimers[key] = setupNewTimer(for: runningTimer.config)
        }
    }

    private func updateRunningTimers(timerConfigs: [MAAViewModel.DailyTaskTimer]) {
        // Initially set all existing timers to be outdated, and update it later
        var outdatedTimerIDs: [String: Bool] = [:]
        runningTimers.keys.forEach { outdatedTimerIDs[$0] = true }

        for config in timerConfigs {
            if config.isEnabled {
                if runningTimers[config.uniqueKey] != nil {
                    outdatedTimerIDs[config.uniqueKey] = false
                } else {
                    print("Found new timer, start to setup it with id: \(config.id.uuidString) hour: \(config.hour) min: \(config.minute)")
                    let newTimer = setupNewTimer(for: config)
                    runningTimers[newTimer.key] = newTimer
                }
            }
        }

        // Cleanup outdated timer
        for (key, outdated) in outdatedTimerIDs {
            if outdated {
                print("Found outdated timer, clening up key: \(key)")
                runningTimers.removeValue(forKey: key)?.stop()
                if pendingRetry?.timerKey == key { cancelPendingRetry() }
            }
        }
    }

    private func setupNewTimer(for timerConfig: MAAViewModel.DailyTaskTimer) -> RunningTimer {
        let nextScheduledDate = createScheduledDate(hour: timerConfig.hour, minute: timerConfig.minute)
        let oneDayInterval = TimeInterval(24 * 3600)
        let timer = Timer(fire: nextScheduledDate, interval: oneDayInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.startDailyTaskIfNeeded(config: timerConfig)
            }
        }
        DispatchQueue.main.async {
            RunLoop.current.add(timer, forMode: .common)
        }

        print("Timer \(timerConfig.uniqueKey) is scheduled at \(nextScheduledDate.description(with: .current))")
        return RunningTimer(config: timerConfig, timer: timer)
    }

    private func createScheduledDate(hour: Int, minute: Int) -> Date {
        // Get the current date and time
        let now = Date()
        let calendar = Calendar(identifier: .gregorian)
        let scheduledDate = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: now)!

        // Check if the given time is earlier than the current time today
        if scheduledDate < now {
            // If so, create a date for tomorrow with the given hour and minute
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: scheduledDate)!
            return tomorrow
        } else {
            // Otherwise, return a date for today with the given hour and minute
            return scheduledDate
        }
    }

    private func startDailyTaskIfNeeded(config: MAAViewModel.DailyTaskTimer, attempt: Int = 1) async {
        guard let viewModel else {
            print("Skip scheduled daily task timer, due to missing viewModel. Timer id: \(config.id)")
            return
        }
        let isDailyTaskRunning = viewModel.status != .idle
        guard !isDailyTaskRunning else {
            print("Skip scheduled daily task timer, due to running daily task. Timer id: \(config.id)")
            return
        }

        guard runningTimers[config.uniqueKey] != nil else { return }
        do {
            try await viewModel.startTasks(isConnectionRetry: attempt > 1)
        } catch MaaCoreError.connectFailed where attempt < Self.maxConnectionAttempts {
            guard runningTimers[config.uniqueKey] != nil, viewModel.status == .idle else { return }
            let nextAttempt = attempt + 1
            viewModel.logWarn("模拟器连接失败，\(Self.retryDelaySeconds) 秒后重试（第 \(nextAttempt)/\(Self.maxConnectionAttempts) 次连接）")
            let task = Task { [weak self] in
                do {
                    try await Task.sleep(for: .seconds(Self.retryDelaySeconds))
                } catch { return }
                guard let self, !Task.isCancelled else { return }
                pendingRetry = nil
                await startDailyTaskIfNeeded(config: config, attempt: nextAttempt)
            }
            cancelPendingRetry()
            pendingRetry = (config.uniqueKey, task)
        } catch {
            viewModel.logStartFailure(error)
        }
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

extension TaskTimerManager.RunningTimer {
    var key: String {
        config.uniqueKey
    }

    func stop() {
        timer.invalidate()
    }
}

// Use uniqueKey to detect if the config changes
private extension MAAViewModel.DailyTaskTimer {
    var uniqueKey: String { "\(id)-\(hour)-\(minute)" }
}

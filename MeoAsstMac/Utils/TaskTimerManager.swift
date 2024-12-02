import AppKit
import Combine
import Foundation

final class TaskTimerManager {
    static let shared = TaskTimerManager()

    struct RunningTimer {
        let config: MAAViewModel.DailyTaskTimer
        let timer: Timer
    }

    private var viewModel: MAAViewModel?
    private var runningTimers: [String: RunningTimer] = [:]

    private var sleepDisabled = false
    var sleepAssertionID: IOPMAssertionID = 0

    private var cancellables = Set<AnyCancellable>()

    private init() {}

    func connectToModel(viewModel: MAAViewModel) {
        self.viewModel = viewModel

        Task {
            await viewModel.$scheduledDailyTaskTimers
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
            preventSystemFromSleepingIfNeeded(await viewModel.preventSystemSleeping)
        }

        print("TaskTimerManager connected")
    }

    func refreshRunningTimersIfNecessary() {
        Task {
            guard let viewModel else {
                print("Skip refreshing daily task timer, due to missing viewModel.")
                return
            }
            let isDailyTaskRunning = await viewModel.status != .idle
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
            }
        }
    }

    private func setupNewTimer(for timerConfig: MAAViewModel.DailyTaskTimer) -> RunningTimer {
        let nextScheduledDate = createScheduledDate(hour: timerConfig.hour, minute: timerConfig.minute)
        let oneDayInterval = TimeInterval(24 * 3600)
        let timer = Timer(fire: nextScheduledDate, interval: oneDayInterval, repeats: true) { [weak self] timer in
            self?.startDailyTaskIfNeeded(timer: timer, config: timerConfig)
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

    private func startDailyTaskIfNeeded(timer: Timer, config: MAAViewModel.DailyTaskTimer) {
        Task {
            guard let viewModel else {
                print("Skip scheduled daily task timer, due to missing viewModel. Timer id: \(config.id)")
                return
            }
            let isDailyTaskRunning = await viewModel.status != .idle
            guard !isDailyTaskRunning else {
                print("Skip scheduled daily task timer, due to running daily task. Timer id: \(config.id)")
                return
            }

            await viewModel.tryStartTasks()
            print("Started daily task by shcedmed timer (\(config.uniqueKey)")
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

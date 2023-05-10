import Foundation
import Combine

final class TaskTimerManager {
    static let shared = TaskTimerManager()

    struct RunningTimer {
        let config: MAAViewModel.DailyTaskTimer
        let timer: Timer
    }

    private var viewModel: MAAViewModel?
    private var runningTimers: [String: RunningTimer] = [:]

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
        }

        print("TaskTimerManager connected")
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

            try await viewModel.startTasks()
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
fileprivate extension MAAViewModel.DailyTaskTimer {
    var uniqueKey: String { "\(id)-\(hour)-\(minute)" }
}

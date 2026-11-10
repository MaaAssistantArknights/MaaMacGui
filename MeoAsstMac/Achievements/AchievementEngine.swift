import Foundation

enum AchievementMetric: String, Codable, Sendable {
    case firstLaunch, battle, medicine, expiringBatch, runBattle
    case roguePass, rogueDifficulty, rogueRetreat, rogueGold, recruitRefresh, clueUse, clueSend
    case copilot, copilotError, mapOutdated, missingFormation, manualStop, scheduledStart
    case peep, hotkey, startup, achievementView, snapshot1, snapshot2, snapshot3, snapshot4, snapshot5, snapshot6
    case creditFight, recruitNoSix, recruitNoSixStreak
}

struct AchievementEvent: Sendable {
    enum Operation: Sendable { case add, maximum, set }
    let id: UUID
    let runID: UUID?
    let taskID: Int32?
    let sequence: UInt64
    let metric: AchievementMetric
    let value: Int
    let operation: Operation

    init(id: UUID = UUID(), runID: UUID? = nil, taskID: Int32? = nil, sequence: UInt64 = 0,
         metric: AchievementMetric, value: Int = 1, operation: Operation = .add) {
        self.id = id; self.runID = runID; self.taskID = taskID; self.sequence = sequence
        self.metric = metric; self.value = value; self.operation = operation
    }
}

struct AchievementProgress: Codable, Equatable {
    var value: Int = 0
    var unlockedAt: Date?
    var conditionVersion: Int = 1
    init() {}
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        value = try c.decodeIfPresent(Int.self, forKey: .value) ?? 0
        unlockedAt = try c.decodeIfPresent(Date.self, forKey: .unlockedAt)
        conditionVersion = try c.decodeIfPresent(Int.self, forKey: .conditionVersion) ?? 1
    }
}

struct AchievementState: Codable, Equatable {
    var schemaVersion: Int = 1
    var progress: [String: AchievementProgress] = [:]
    var recentEventIDs: [UUID] = []
    var runBattles: [String: Int] = [:]
    init() {}
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        progress = try c.decodeIfPresent([String: AchievementProgress].self, forKey: .progress) ?? [:]
        recentEventIDs = try c.decodeIfPresent([UUID].self, forKey: .recentEventIDs) ?? []
        runBattles = try c.decodeIfPresent([String: Int].self, forKey: .runBattles) ?? [:]
    }
}

struct AchievementEngine {
    private(set) var state: AchievementState
    init(state: AchievementState = AchievementState()) { self.state = state }

    mutating func consume(_ event: AchievementEvent, now: Date = .now) -> [String] {
        guard event.value >= 0, !state.recentEventIDs.contains(event.id) else { return [] }
        if case .maximum = event.operation {
            let changesProgress = AchievementDefinition.all.contains { definition in
                guard definition.metric == event.metric else { return false }
                let current = state.progress[definition.id] ?? AchievementProgress()
                guard current.conditionVersion == definition.conditionVersion else { return false }
                let next = max(current.value, event.value)
                return next != current.value || (current.unlockedAt == nil && next >= definition.target)
            }
            // Maximum observations are already idempotent. A displayed preview
            // must not append an event ID or rewrite disk once its progress is unchanged.
            guard changesProgress else { return [] }
        }
        state.recentEventIDs.append(event.id)
        if state.recentEventIDs.count > 2048 { state.recentEventIDs.removeFirst(state.recentEventIDs.count - 2048) }
        var unlocked = apply(metric: event.metric, value: event.value, operation: event.operation, now: now)
        if event.metric == .battle, let run = event.runID {
            let key = run.uuidString
            let previous = state.runBattles[key] ?? 0
            let next = Self.saturatedAdd(previous, event.value)
            state.runBattles[key] = next
            // Only active/recent runs are needed; their IDs carry no account identity.
            if state.runBattles.count > 32 {
                state.runBattles = [key: next]
            }
            unlocked += apply(metric: .runBattle, value: next, operation: .maximum, now: now)
        }
        return unlocked
    }

    private mutating func apply(metric: AchievementMetric, value: Int, operation: AchievementEvent.Operation, now: Date) -> [String] {
        var unlocked: [String] = []
        for definition in AchievementDefinition.all where definition.metric == metric {
            var progress = state.progress[definition.id] ?? AchievementProgress()
            guard progress.conditionVersion == definition.conditionVersion else { continue }
            switch operation {
            case .add: progress.value = Self.saturatedAdd(progress.value, value)
            case .maximum: progress.value = max(progress.value, value)
            case .set:
                // A six-star streak reset must not regress an unlocked display.
                if progress.unlockedAt == nil { progress.value = value }
            }
            if progress.unlockedAt == nil, progress.value >= definition.target {
                progress.unlockedAt = now
                unlocked.append(definition.id)
            }
            state.progress[definition.id] = progress
        }
        return unlocked
    }

    private static func saturatedAdd(_ a: Int, _ b: Int) -> Int {
        let (value, overflow) = a.addingReportingOverflow(b)
        return overflow ? Int.max : value
    }
}

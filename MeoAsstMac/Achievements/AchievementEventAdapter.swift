import Foundation
import CoreFoundation

/// A single native callback listener creates envelopes. Identical payloads from
/// distinct receives remain distinct events; no global JSON hash is used.
struct AchievementEventAdapter {
    private struct TaskContext {
        let runID: UUID
        var type: String
        var active: Bool = false
    }
    private var tasks: [Int32: TaskContext] = [:]
    private var sequence: UInt64 = 0

    mutating func resetSession() { tasks.removeAll() }
    mutating func register(taskID: Int32, type: String = "", runID: UUID = UUID()) {
        tasks[taskID] = TaskContext(runID: runID, type: type)
    }

    mutating func consume(code: Int, data: Data) -> [AchievementEvent] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        sequence &+= 1
        if code == 2, json["what"] as? String == "ScreencapCost",
           let details = json["details"] as? [String: Any], let avg = Self.integer(details["avg"]), avg >= 0 {
            let metrics: [AchievementMetric] = avg >= 800 ? [.snapshot1] : avg >= 400 ? [.snapshot2] :
                avg < 5 ? [.snapshot3, .snapshot4, .snapshot5, .snapshot6] :
                avg < 10 ? [.snapshot3, .snapshot4, .snapshot5] : avg < 100 ? [.snapshot3, .snapshot4] : [.snapshot3]
            return metrics.map { AchievementEvent(sequence: sequence, metric: $0, operation: .maximum) }
        }
        if code == 3 {
            // A delayed prior completion must not erase newly registered tasks.
            if let finished = json["finished_tasks"] as? [Any] {
                for id in finished { if let number = Self.integer(id), let key = Int32(exactly: number) { tasks.removeValue(forKey: key) } }
            }
            return []
        }
        guard let taskNumber = Self.integer(json["taskid"]), let taskID = Int32(exactly: taskNumber),
              var task = tasks[taskID], let chain = json["taskchain"] as? String else { return [] }
        if code == 10001 {
            guard task.type.isEmpty || task.type == chain else { return [] }
            task.type = chain; task.active = true; tasks[taskID] = task; return []
        }
        guard task.active, task.type == chain else { return [] }
        func event(_ metric: AchievementMetric, _ value: Int = 1, _ operation: AchievementEvent.Operation = .add) -> AchievementEvent {
            AchievementEvent(runID: task.runID, taskID: taskID, sequence: sequence, metric: metric, value: value, operation: operation)
        }
        if code == 10002 || code == 10000 || code == 10004 {
            tasks.removeValue(forKey: taskID)
            if ["Copilot", "SSSCopilot", "ParadoxCopilot"].contains(task.type) {
                if code == 10002 { return [event(.copilot)] }
                if code == 10000 { return [event(.copilotError)] }
            }
            return []
        }
        let details = json["details"] as? [String: Any] ?? [:]
        let what = json["what"] as? String ?? ""
        if code == 20003 {
            switch (task.type, what) {
            case ("Fight", "StageDrops"):
                // cur_times is the successful batch count, not a cumulative run counter.
                // Match WPF's fallback to one when that optional count is unavailable.
                guard details["stats"] is [Any] else { return [] }
                let count = Self.integer(details["cur_times"]) ?? 1
                guard count >= 0 else { return [] }
                return [event(.battle, max(count, 1))]
            case ("Fight", "UseMedicine"):
                guard let count = Self.integer(details["count"]), count > 0 else { return [] }
                var result = [event(.medicine, count)]
                if Self.boolean(details["is_expiring"]) == true { result.append(event(.expiringBatch, count, .maximum)) }
                return result
            case ("Recruit", "RecruitTagsRefreshed"): return [event(.recruitRefresh)]
            case ("Recruit", "RecruitResult"):
                guard let level = Self.integer(details["level"]), (1...6).contains(level) else { return [] }
                // WPF counts recognized tag results, not confirmations; a six-star
                // result resets its streak to one under the pinned definition.
                if level == 6 { return [event(.recruitNoSixStreak, 1, .set)] }
                return [event(.recruitNoSix), event(.recruitNoSixStreak)]
            case ("Roguelike", "RoguelikeInvestment"):
                guard let deposit = Self.integer(details["deposit"]), deposit >= 0 else { return [] }
                return [event(.rogueGold, deposit, .maximum)]
            case ("Roguelike", "RoguelikeSettlement"):
                guard Self.boolean(details["game_pass"]) == true, let difficulty = Self.integer(details["difficulty"]), difficulty >= 0 else { return [] }
                return [event(.rogueDifficulty, difficulty, .maximum)]
            case (_, "UnsupportedLevel") where ["Copilot", "SSSCopilot", "ParadoxCopilot"].contains(task.type):
                return [event(.mapOutdated, 1, .maximum)]
            default: return []
            }
        }
        if code == 20000, ["Copilot", "SSSCopilot", "ParadoxCopilot"].contains(task.type), json["subtask"] as? String == "BattleFormationTask",
           json["why"] as? String == "OperatorMissing", let opers = details["opers"] as? [String: Any], opers.count >= 2 {
            return [event(.missingFormation, 1, .maximum)]
        }
        guard json["subtask"] as? String == "ProcessTask", let rawName = details["task"] as? String else { return [] }
        let name = rawName.split(separator: "@").last.map(String.init) ?? rawName
        if code == 20001, task.type == "Roguelike" {
            if name == "GamePass" { return [event(.roguePass)] }
            if name == "ExitThenAbandon" { return [event(.rogueRetreat)] }
        }
        if code == 20002 {
            if task.type == "Infrast", name == "UnlockClues" { return [event(.clueUse)] }
            if task.type == "Infrast", name == "SendClues" { return [event(.clueSend)] }
            if task.type == "Mall", name == "StageDrops-Stars-3" { return [event(.creditFight)] }

        }
        return []
    }

    private static func boolean(_ value: Any?) -> Bool? {
        guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { return nil }
        return number.boolValue
    }

    private static func integer(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let string = number.stringValue
        return Int(string)
    }
}

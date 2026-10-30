import Foundation

@main struct AchievementTests {
    @MainActor static func main() throws {
        var checks = 0
        func check(_ value: @autoclosure () throws -> Bool, _ label: String) rethrows {
            checks += 1
            let result = try value()
            precondition(result, label)
        }
        check(Set(AchievementDefinition.all.map(\.id)).count == AchievementDefinition.all.count, "unique stable definition IDs")
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        for definition in AchievementDefinition.all {
            var engine = AchievementEngine()
            let below = AchievementEvent(metric: definition.metric, value: definition.target - 1, operation: .maximum)
            _ = engine.consume(below, now: now)
            check(engine.state.progress[definition.id]?.unlockedAt == nil, "below threshold: \(definition.id)")
            let event = AchievementEvent(metric: definition.metric, value: definition.target, operation: .maximum)
            let first = engine.consume(event, now: now)
            check(first.contains(definition.id), "threshold: \(definition.id)")
            check(engine.consume(event, now: now).isEmpty, "same envelope: \(definition.id)")
            _ = engine.consume(.init(metric: definition.metric, value: Int.max, operation: .maximum), now: now.addingTimeInterval(10))
            check(engine.state.progress[definition.id]?.unlockedAt == now, "unlock time stable: \(definition.id)")
        }
        var engine = AchievementEngine()
        let run = UUID()
        let event = AchievementEvent(runID: run, taskID: 42, sequence: 1, metric: .battle, value: 5)
        _ = engine.consume(event)
        _ = engine.consume(event)
        _ = engine.consume(.init(runID: run, taskID: 42, sequence: 2, metric: .battle, value: 5))
        check(engine.state.progress["SanitySpender1"]?.value == 10, "same payload, distinct real events")
        _ = engine.consume(.init(runID: run, metric: .battle, value: 90))
        check(engine.state.progress["OverLimitAgent"]?.unlockedAt != nil, "per-run completed battles")
        _ = engine.consume(.init(runID: UUID(), metric: .battle, value: 1))
        check(engine.state.progress["OverLimitAgent"]?.value == 100, "new run is not added to old run")
        let original = engine.state.progress
        _ = engine.consume(.init(metric: .battle, value: -1))
        check(engine.state.progress == original, "negative event rejected")
        _ = engine.consume(.init(metric: .medicine, value: Int.max))
        _ = engine.consume(.init(metric: .medicine, value: Int.max))
        check(engine.state.progress["SanitySaver1"]?.value == Int.max, "overflow saturates")
        let streakDef = AchievementDefinition.all.first { $0.metric == .recruitNoSixStreak }!
        var streak = AchievementEngine()
        _ = streak.consume(.init(metric: .recruitNoSixStreak, value: 12, operation: .set), now: now)
        check(streak.state.progress[streakDef.id]?.value == 12, "streak set applies before unlock")
        _ = streak.consume(.init(metric: .recruitNoSixStreak, value: 3, operation: .set), now: now)
        check(streak.state.progress[streakDef.id]?.value == 3, "streak reset applies before unlock")
        check(streak.consume(.init(metric: .recruitNoSixStreak, value: streakDef.target, operation: .set), now: now) == [streakDef.id], "streak set can unlock")
        check(streak.consume(.init(metric: .recruitNoSixStreak, value: 1, operation: .set), now: now.addingTimeInterval(10)).isEmpty, "post-unlock streak reset publishes no unlock")
        check(streak.state.progress[streakDef.id]?.value == streakDef.target && streak.state.progress[streakDef.id]?.unlockedAt == now, "post-unlock streak reset does not regress the display")
        var adapter = AchievementEventAdapter()
        func data(_ json: [String: Any]) throws -> Data { try JSONSerialization.data(withJSONObject: json) }
        func payload(_ what: String, _ details: [String: Any], id: Int = 42, chain: String = "Fight") -> [String: Any] {
            ["taskid": id, "taskchain": chain, "what": what, "details": details]
        }
        let raw = try data(payload("StageDrops", ["cur_times": 3, "stats": []]))
        check(adapter.consume(code: 20003, data: raw).isEmpty, "unregistered task ignored")
        adapter.register(taskID: 42, type: "Fight", runID: run)
        check(adapter.consume(code: 20003, data: raw).isEmpty, "prestart event ignored")
        _ = adapter.consume(code: 10001, data: try data(["taskid": 42, "taskchain": "Fight"]))
        let batch1 = adapter.consume(code: 20003, data: raw)
        let batch2 = adapter.consume(code: 20003, data: raw)
        check(batch1.first?.value == 3 && batch2.first?.value == 3, "batch count is not cumulative")
        check(batch1.first?.id != batch2.first?.id, "distinct envelopes for identical native receives")
        try check(adapter.consume(code: 20003, data: try data(payload("FightTimes", ["times_finished": 100]))).isEmpty, "no double count FightTimes")
        try check(adapter.consume(code: 20003, data: try data(payload("StageDrops", ["cur_times": -1, "stats": []]))).isEmpty, "bad count ignored")
        try check(adapter.consume(code: 20003, data: try data(payload("UseMedicine", ["count": true]))).isEmpty, "boolean is not count")
        try check(adapter.consume(code: 20003, data: data(payload("StageDrops", [:]))).isEmpty, "malformed drops do not invent a battle")
        let medicine = adapter.consume(code: 20003, data: try data(payload("UseMedicine", ["count": 8, "is_expiring": true])))
        check(medicine.count == 2 && medicine.last?.metric == .expiringBatch, "known expiring property")
        try check(adapter.consume(code: 20003, data: try data(payload("UseMedicine", ["count": 1, "is_expiring": false]))).count == 1, "ordinary potion")
        _ = adapter.consume(code: 3, data: try data(["finished_tasks": [1]]))
        check(!adapter.consume(code: 20003, data: raw).isEmpty, "late old completion does not drop current task")
        _ = adapter.consume(code: 10004, data: try data(["taskid": 42, "taskchain": "Fight"]))
        check(adapter.consume(code: 20003, data: raw).isEmpty, "stopped task ignored")
        adapter.register(taskID: 8, type: "Infrast")
        _ = adapter.consume(code: 10001, data: try data(["taskid": 8, "taskchain": "Infrast"]))
        for name in ["SendClues", "Infrast@SendClues", "UnlockClues", "Infrast@UnlockClues"] {
            let opened: [String: Any] = ["taskid": 8, "taskchain": "Infrast", "subtask": "ProcessTask", "details": ["task": name, "action": "ClickSelf"]]
            try check(adapter.consume(code: 20002, data: data(opened)).isEmpty, "ambiguous clue action is not a confirmed success")
        }
        adapter.register(taskID: 7, type: "Roguelike")
        _ = adapter.consume(code: 10001, data: try data(["taskid": 7, "taskchain": "Roguelike"]))
        let failedSettlement = payload("RoguelikeSettlement", ["game_pass": false, "difficulty": 15], id: 7, chain: "Roguelike")
        try check(adapter.consume(code: 20003, data: try data(failedSettlement)).isEmpty, "failed exploration gives no difficulty")
        try check(adapter.consume(code: 20003, data: data(payload("RoguelikeSettlement", ["game_pass": 1, "difficulty": 15], id: 7, chain: "Roguelike"))).isEmpty, "numeric success flag rejected")
        let noDifficulty = payload("RoguelikeSettlement", ["game_pass": true], id: 7, chain: "Roguelike")
        try check(adapter.consume(code: 20003, data: try data(noDifficulty)).isEmpty, "missing difficulty not invented")
        let settlement = payload("RoguelikeSettlement", ["game_pass": true, "difficulty": 15], id: 7, chain: "Roguelike")
        try check(adapter.consume(code: 20003, data: try data(settlement)).first?.metric == .rogueDifficulty, "confirmed difficulty")
        let gold = payload("RoguelikeInvestment", ["deposit": 999], id: 7, chain: "Roguelike")
        try check(adapter.consume(code: 20003, data: try data(gold)).first?.operation == .maximum, "deposit maximum")
        for (cost, expected) in [(4,4),(5,3),(9,3),(10,2),(99,2),(100,1),(399,1),(400,1),(799,1),(800,1)] {
            try check(adapter.consume(code: 2, data: try data(["what": "ScreencapCost", "details": ["avg": cost]])).count == expected, "screenshot boundary \(cost)")
        }
        adapter.resetSession()
        try check(adapter.consume(code: 20003, data: try data(settlement)).isEmpty, "session reset discards ownership")
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }
        let suite = "plus.maa.achievement.tests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let url = temp.appendingPathComponent("state.json")
        let store = AchievementStore(url: url, defaults: defaults, observeFeatures: false)
        store.record(.init(metric: .medicine))
        check(store.engine.state.progress["SanitySaver1"]?.unlockedAt != nil, "stored progress")
        store.record(.init(metric: .peep, operation: .maximum))
        let savedIDs = store.engine.state.recentEventIDs
        let sentinel = Date(timeIntervalSince1970: 10)
        try FileManager.default.setAttributes([.modificationDate: sentinel], ofItemAtPath: url.path)
        for _ in 0..<100 { store.record(.init(metric: .peep, operation: .maximum)) }
        check(store.engine.state.recentEventIDs == savedIDs, "unchanged preview observations do not append envelopes")
        let modification = try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
        check(modification == sentinel, "unchanged preview observations do not write disk")
        let reloaded = AchievementStore(url: url, defaults: defaults, observeFeatures: false)
        check(reloaded.engine.state.progress["SanitySaver1"]?.value == 1, "restart roundtrip")
        reloaded.showUnlockHints = false
        reloaded.record(.init(metric: .copilot))
        check(reloaded.latestUnlocks.isEmpty, "disabled hints")
        reloaded.resetWithBackup()
        check(reloaded.engine.state.progress.isEmpty, "explicit reset")
        try check(try FileManager.default.contentsOfDirectory(atPath: temp.path).contains(where: { $0.contains("backup-") }), "backup before reset")
        try Data("bad data".utf8).write(to: url)
        let recovered = AchievementStore(url: url, defaults: defaults, observeFeatures: false)
        check(recovered.message != nil && recovered.engine.state.progress.isEmpty, "bad storage recovery")
        try check(try FileManager.default.contentsOfDirectory(atPath: temp.path).contains(where: { $0.contains("corrupt-") }), "corrupt file preserved")
        let future = Data("{\"schemaVersion\":2}".utf8)
        try future.write(to: url)
        let readonly = AchievementStore(url: url, defaults: defaults, observeFeatures: false)
        readonly.record(.init(metric: .firstLaunch))
        try check(try Data(contentsOf: url) == future, "future schema not overwritten")
        try Data("{\"schemaVersion\":1,\"progress\":{\"UnknownFutureDefinition\":{\"value\":42}}}".utf8).write(to: url)
        let migrated = AchievementStore(url: url, defaults: defaults, observeFeatures: false)
        migrated.record(.init(metric: .firstLaunch))
        check(migrated.engine.state.progress["UnknownFutureDefinition"]?.value == 42, "unknown progress preserved")
        let blocker = temp.appendingPathComponent("not-a-directory")
        try Data().write(to: blocker)
        let failing = AchievementStore(url: blocker.appendingPathComponent("state.json"), defaults: defaults, observeFeatures: false)
        failing.record(.init(metric: .firstLaunch))
        check(failing.engine.state.progress.isEmpty && failing.latestUnlocks.isEmpty && failing.message != nil, "failed persistence publishes no reward")
        print("Achievements: \(checks) assertions passed")
    }
}

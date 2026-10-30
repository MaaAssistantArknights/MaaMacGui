import Foundation

@main struct InventoryTargetTests {
    static func main() throws {
        var count = 0
        func check(_ value: @autoclosure () throws -> Bool, _ label: String) rethrows {
            count += 1
            let result = try value()
            precondition(result, label)
        }
        func rejects(_ label: String, as expected: InventoryTargetError? = nil, _ action: () throws -> Void) {
            count += 1
            do { try action(); preconditionFailure(label) }
            catch let error as InventoryTargetError {
                if let expected, error != expected { preconditionFailure("\(label): expected \(expected), got \(error)") }
            } catch { preconditionFailure("\(label): unexpected error \(error)") }
        }
        let scope = InventoryScope(connection: "adb", server: "CN", profile: "Default")
        let other = InventoryScope(connection: "adb2", server: "CN", profile: "Default")
        let target = InventoryTarget(itemID: "30012", quantity: 10)
        let known: Set<String> = ["30012"]
        check(InventoryTargetPlanner.supportsInventory(classification: "MATERIAL"), "depot material domain")
        check(!InventoryTargetPlanner.supportsInventory(classification: "NONE"), "reputation 5001 is not inventory")
        check(!InventoryTargetPlanner.supportsInventory(classification: "NORMAL"), "version-dependent basic-item extension excluded")
        check(!InventoryTargetPlanner.supportsInventory(classification: nil), "unknown classification excluded")
        var adapter = InventorySnapshotAdapter()
        rejects("missing snapshot") { _ = try InventoryTargetPlanner.plan(target: target, snapshot: nil, knownItems: known) }
        rejects("incomplete snapshot") { try adapter.capture(items: [:], complete: false, scope: scope) }
        rejects("negative snapshot") { try adapter.capture(items: ["30012": -1], complete: true, scope: scope) }
        try adapter.capture(items: [:], complete: true, scope: scope)
        try check(try InventoryTargetPlanner.plan(target: target, snapshot: adapter.snapshot, knownItems: known).requiredDrops == 10, "complete absent item means zero")
        check(adapter.usableSnapshot(scope: other) == nil, "different connection")
        for inventory in [0, 1, 9, 10, 11, Int.max] {
            try adapter.capture(items: ["30012": inventory], complete: true, scope: scope)
            let plan = try InventoryTargetPlanner.plan(target: target, snapshot: adapter.snapshot, knownItems: known)
            check(plan.requiredDrops == max(10 - min(inventory, 10), 0), "safe difference")
            check(plan.startInventory == inventory, "frozen base")
        }
        for quantity in [-1, Int.max] {
            rejects("bad quantity", as: .invalidTarget) { _ = try InventoryTargetPlanner.plan(target: .init(itemID: "30012", quantity: quantity), snapshot: adapter.snapshot, knownItems: known) }
        }
        rejects("reputation 5001 rejected") { _ = try InventoryTargetPlanner.plan(target: .init(itemID: "5001", quantity: 1), snapshot: adapter.snapshot, knownItems: known) }
        rejects("unknown material") { _ = try InventoryTargetPlanner.plan(target: .init(itemID: "wrong", quantity: 1), snapshot: adapter.snapshot, knownItems: known) }
        rejects("multiple targets") { try InventoryTargetPlanner.validateQueue(targetIndices: [0, 1], firstEnabledIndex: 0) }
        rejects("unsafe order") { try InventoryTargetPlanner.validateQueue(targetIndices: [1], firstEnabledIndex: 0) }
        try InventoryTargetPlanner.validateQueue(targetIndices: [0], firstEnabledIndex: 0)
        try InventoryTargetPlanner.validateQueue(targetIndices: [], firstEnabledIndex: nil)
        try adapter.capture(items: ["30012": 5], complete: true, scope: scope)
        let initialPlan = try InventoryTargetPlanner.plan(target: target, snapshot: adapter.snapshot, knownItems: known)
        try InventoryTargetPlanner.validateFrozen(initialPlan, itemID: target.itemID, snapshot: adapter.snapshot)
        rejects("different generation rejected") {
            try InventoryTargetPlanner.validateFrozen(initialPlan, itemID: target.itemID,
                snapshot: InventorySnapshot(generation: UUID(), scope: scope, capturedAt: .now, items: ["30012": 5]))
        }
        let generation = adapter.snapshot!.generation
        adapter.beginRun(id: UUID(), taskIDs: [42, 43])
        try check(try adapter.merge(taskID: 99, cumulative: ["30012": 9], scope: scope).isEmpty, "foreign task")
        for value in [1, 1, 3, 2, 3, 5] {
            _ = try adapter.merge(taskID: 42, cumulative: ["30012": value], scope: scope)
        }
        check(adapter.snapshot?.items["30012"] == 10, "cumulative highwater")
        rejects("late prior drops cannot change frozen base") {
            try InventoryTargetPlanner.validateFrozen(initialPlan, itemID: target.itemID, snapshot: adapter.snapshot)
        }
        _ = try adapter.merge(taskID: 43, cumulative: ["30012": 5], scope: scope)
        check(adapter.snapshot?.items["30012"] == 15, "same payload distinct task counts")
        check(adapter.snapshot?.generation == generation, "generation stable during run")
        let newRun = UUID()
        adapter.beginRun(id: newRun, taskIDs: [44])
        _ = try adapter.merge(taskID: 42, cumulative: ["30012": 99], scope: scope)
        _ = try adapter.merge(taskID: 44, cumulative: ["30012": 1], scope: scope)
        check(adapter.snapshot?.items["30012"] == 16, "new run ignores old task")
        try adapter.capture(items: ["30012": Int.max], complete: true, scope: scope)
        adapter.beginRun(id: UUID(), taskIDs: [1])
        rejects("overflow invalidates", as: .inventoryOverflow) { _ = try adapter.merge(taskID: 1, cumulative: ["30012": 1], scope: scope) }
        check(adapter.snapshot == nil, "overflow invalid snapshot")
        var config = FightConfiguration()
        check(config.inventoryTarget == nil, "legacy default")
        config.drops = ["30012": 3]
        let normal = try JSONSerialization.jsonObject(with: JSONEncoder().encode(config.params)) as! [String: Any]
        check(normal["inventoryTarget"] == nil, "UI target excluded")
        check((normal["drops"] as? [String: Int]) == config.drops, "normal mode unchanged")
        config.inventoryTarget = target
        rejects("unprepared params fail closed") { _ = try JSONEncoder().encode(config.params) }
        let encoded = try PropertyListEncoder().encode(config)
        let restored = try PropertyListDecoder().decode(FightConfiguration.self, from: encoded)
        check(restored.inventoryTarget == target, "plist roundtrip")
        check(restored.drops == ["30012": 3], "retains normal preference")
        let plan = InventoryTargetPlan(generation: UUID(), startInventory: 8, requiredDrops: 2)
        let prepared = config.preparingInventoryTarget(plan)
        let params = try JSONSerialization.jsonObject(with: JSONEncoder().encode(prepared.params)) as! [String: Any]
        check((params["drops"] as? [String: Int]) == ["30012": 2], "prepared delta")
        check(config.inventoryTarget == target, "persisted preference not mutated")
        adapter.invalidate()
        check(adapter.snapshot == nil && adapter.runID == nil, "reconnect invalidates")
        print("InventoryTarget: \(count) assertions passed")
    }
}

#!/usr/bin/env python3
"""Run the production inventory callback branches with an isolated ViewModel double."""

from pathlib import Path
import subprocess
import tempfile


root = Path(__file__).resolve().parents[1]
messages = (root / "MeoAsstMac/Core/MaaMessage.swift").read_text()
model = (root / "MeoAsstMac/Model/MAAViewModel.swift").read_text()


def function(source, signature):
    start = source.index(signature)
    body = source.index("{", start)
    depth = 0
    for end in range(body, len(source)):
        if source[end] == "{":
            depth += 1
        elif source[end] == "}":
            depth -= 1
            if depth == 0:
                return source[start : end + 1]
    raise ValueError(f"Unclosed function: {signature}")


extra = function(messages, "    private func processSubTaskExtraInfo(")
# Keep the actual account-switch case and the complete Fight inventory branch.
# Logging and the rest of the callback's UI work are outside this probe's scope.
account = extra[extra.index('        case "AccountSwitch":') : extra.index('        case "StageInfo":')]
stage = extra[extra.index('            if info.taskchain == "Fight", let taskID = info.taskid {') : extra.index("            let drops = dropInfo.stats")]
invalidate = function(model, "    func invalidateInventory()")

probe = r'''
import Foundation

struct DropItem {
    let itemId: String?
    let quantity: Int
    let addQuantity: Int
}
struct DropInfo { let stats: [DropItem] }
struct Details { subscript(_ key: String) -> String { get throws { "" } } }
struct Info {
    let what: String
    let taskchain: String
    let taskid: Int32?
    var details = Details()
}
struct TestLogger { func debug(_ message: String) {} }
let logger = TestLogger()
enum TestLog { case accountSwitch(to: String) }

final class Probe {
    var inventory = InventorySnapshotAdapter()
    let inventoryScope = InventoryScope(connection: "adb", server: "CN", profile: "Default")
    var inventoryDepotTaskID: Int32?
    var inventoryDepotScope: InventoryScope?
    var pendingInventoryDepot: [String: Int]?
    var currentInventorySnapshot: InventorySnapshot? { inventory.usableSnapshot(scope: inventoryScope) }
    func logTrace(_ message: TestLog) {}
    func logError(_ message: String) {}
''' + invalidate + r'''
    func process(_ info: Info, drops dropInfo: DropInfo = DropInfo(stats: [])) {
        switch info.what {
''' + account + r'''
        case "StageDrops":
''' + stage + r'''
        default: break
        }
    }
}

@main struct Main {
    static func main() throws {
        var checks = 0
        func check(_ value: Bool, _ message: String) {
            checks += 1
            precondition(value, message)
        }
        func make() throws -> Probe {
            let model = Probe()
            try model.inventory.capture(items: ["30012": 5], complete: true, scope: model.inventoryScope)
            model.inventory.beginRun(id: UUID(), taskIDs: [42, 43])
            return model
        }
        func report(_ model: Probe, quantity: Int, added: Int, taskID: Int32 = 42) {
            model.process(Info(what: "StageDrops", taskchain: "Fight", taskid: taskID),
                          drops: DropInfo(stats: [DropItem(itemId: "30012", quantity: quantity, addQuantity: added)]))
        }

        let switched = try make()
        switched.inventoryDepotTaskID = 77
        switched.inventoryDepotScope = switched.inventoryScope
        switched.pendingInventoryDepot = ["30012": 99]
        switched.process(Info(what: "AccountSwitch", taskchain: "StartUp", taskid: nil))
        check(switched.currentInventorySnapshot == nil, "account switch rejects previous account inventory")
        check(switched.inventory.runID == nil, "account switch releases Fight ownership")
        check(switched.inventoryDepotTaskID == nil && switched.inventoryDepotScope == nil && switched.pendingInventoryDepot == nil,
              "account switch discards pending recognition so late completion cannot restore old inventory")
        report(switched, quantity: 100, added: 100)
        check(switched.currentInventorySnapshot == nil, "late Fight drops cannot revive previous account snapshot")
        do {
            _ = try InventoryTargetPlanner.plan(target: InventoryTarget(itemID: "30012", quantity: 10),
                                                snapshot: switched.currentInventorySnapshot, knownItems: ["30012"])
            preconditionFailure("new account must require Depot recognition")
        } catch InventoryTargetError.recognitionRequired { checks += 1 }
        try switched.inventory.capture(items: ["30012": 1], complete: true, scope: switched.inventoryScope)
        let plan = try InventoryTargetPlanner.plan(target: InventoryTarget(itemID: "30012", quantity: 10),
                                                   snapshot: switched.currentInventorySnapshot, knownItems: ["30012"])
        check(plan.requiredDrops == 9, "fresh recognition uses new account stock")

        let drops = try make()
        // Core adds the current drop into stats.quantity BEFORE emitting addQuantity.
        // The display's '(+N)' is the latest battle's delta, already included in quantity.
        // Source: MaaCore/Task/Fight/StageDropsTaskPlugin.cpp, drop_info_callback().
        for (quantity, added, expected) in [(2, 2, 7), (2, 2, 7), (5, 3, 10), (3, 1, 10), (5, 0, 10)] {
            report(drops, quantity: quantity, added: added)
            check(drops.currentInventorySnapshot?.items["30012"] == expected,
                  "cumulative total includes addQuantity once, even on duplicate or out-of-order callbacks")
        }
        let reached = try InventoryTargetPlanner.plan(target: InventoryTarget(itemID: "30012", quantity: 10),
                                                      snapshot: drops.currentInventorySnapshot, knownItems: ["30012"])
        check(reached.requiredDrops == 0, "later target run skips after cumulative stock reaches goal")
        report(drops, quantity: 2, added: 2, taskID: 43)
        check(drops.currentInventorySnapshot?.items["30012"] == 12, "distinct Fight task has its own watermark")
        report(drops, quantity: 99, added: 99, taskID: 99)
        check(drops.currentInventorySnapshot?.items["30012"] == 12, "foreign task drops ignored")
        drops.process(Info(what: "StageDrops", taskchain: "Copilot", taskid: 42),
                      drops: DropInfo(stats: [DropItem(itemId: "30012", quantity: 99, addQuantity: 99)]))
        check(drops.currentInventorySnapshot?.items["30012"] == 12, "non-Fight report ignored")
        let missingID = try make()
        missingID.process(Info(what: "StageDrops", taskchain: "Fight", taskid: 42),
                          drops: DropInfo(stats: [DropItem(itemId: nil, quantity: 1, addQuantity: 1)]))
        check(missingID.currentInventorySnapshot == nil, "unidentified drops invalidate snapshot")
        let duplicateID = try make()
        let item = DropItem(itemId: "30012", quantity: 1, addQuantity: 1)
        duplicateID.process(Info(what: "StageDrops", taskchain: "Fight", taskid: 42), drops: DropInfo(stats: [item, item]))
        check(duplicateID.currentInventorySnapshot == nil, "ambiguous duplicate IDs invalidate snapshot")
        print("Inventory callbacks: \(checks) production-branch assertions passed")
    }
}
'''

with tempfile.TemporaryDirectory(prefix="maa-inventory-callbacks-") as temporary:
    path = Path(temporary)
    (path / "Probe.swift").write_text(probe)
    subprocess.run(
        ["swiftc", "-parse-as-library", str(root / "MeoAsstMac/Model/InventoryTarget.swift"),
         str(path / "Probe.swift"), "-o", str(path / "probe")],
        check=True,
    )
    subprocess.run([str(path / "probe")], check=True)

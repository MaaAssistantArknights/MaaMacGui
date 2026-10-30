import Foundation

struct InventoryTarget: Codable, Hashable, Sendable {
    var itemID: String
    var quantity: Int
}

struct InventoryScope: Equatable, Sendable {
    let connection: String
    let server: String
    let profile: String
}

struct InventorySnapshot: Equatable, Sendable {
    let generation: UUID
    let scope: InventoryScope
    let capturedAt: Date
    var items: [String: Int]
}

enum InventoryTargetError: LocalizedError {
    case recognitionRequired, invalidTarget, multipleTargets, unsafeOrder, stalePreparation, inventoryOverflow

    var errorDescription: String? {
        switch self {
        case .recognitionRequired: String(localized: "Inventory.RecognitionRequired")
        case .invalidTarget: String(localized: "Inventory.InvalidTarget")
        case .multipleTargets: String(localized: "Inventory.MultipleTargets")
        case .unsafeOrder: String(localized: "Inventory.UnsafeOrder")
        case .stalePreparation: String(localized: "Inventory.StalePreparation")
        case .inventoryOverflow: String(localized: "Inventory.Overflow")
        }
    }
}

/// Session-only state. A disk cache cannot establish the currently connected account.
struct InventorySnapshotAdapter {
    private(set) var snapshot: InventorySnapshot?
    private var watermarks: [Int32: [String: Int]] = [:]
    private(set) var runID: UUID?
    private var acceptedTaskIDs: Set<Int32> = []

    mutating func invalidate() {
        snapshot = nil
        watermarks.removeAll()
        acceptedTaskIDs.removeAll()
        runID = nil
    }

    mutating func capture(items: [String: Int], complete: Bool, scope: InventoryScope, now: Date = .now) throws {
        invalidate()
        guard complete, items.values.allSatisfy({ $0 >= 0 }) else {
            throw InventoryTargetError.recognitionRequired
        }
        snapshot = InventorySnapshot(generation: UUID(), scope: scope, capturedAt: now, items: items)
    }

    func usableSnapshot(scope: InventoryScope) -> InventorySnapshot? {
        guard let snapshot, snapshot.scope == scope else { return nil }
        return snapshot
    }

    mutating func beginRun(id: UUID, taskIDs: Set<Int32>) {
        runID = id
        acceptedTaskIDs = taskIDs
        watermarks.removeAll()
    }

    /// Core stats.quantity is cumulative per Fight task, not the current drop amount.
    /// Repeated and out-of-order values therefore contribute only their high-water delta.
    mutating func merge(taskID: Int32, cumulative: [String: Int], scope: InventoryScope) throws -> [String: Int] {
        guard runID != nil, acceptedTaskIDs.contains(taskID), var current = usableSnapshot(scope: scope) else {
            return [:]
        }
        guard cumulative.values.allSatisfy({ $0 >= 0 }) else {
            invalidate()
            throw InventoryTargetError.recognitionRequired
        }
        var marks = watermarks[taskID] ?? [:]
        var increments: [String: Int] = [:]
        for (item, count) in cumulative {
            let previous = marks[item] ?? 0
            let delta = max(count - previous, 0)
            let (updated, overflow) = (current.items[item] ?? 0).addingReportingOverflow(delta)
            guard !overflow else {
                invalidate()
                // 运行期累计溢出与目标配置无关，不复用配置校验的 invalidTarget 文案。
                throw InventoryTargetError.inventoryOverflow
            }
            current.items[item] = updated
            marks[item] = max(count, previous)
            if delta > 0 { increments[item] = delta }
        }
        snapshot = current
        watermarks[taskID] = marks
        return increments
    }
}

struct InventoryTargetPlan: Equatable {
    let generation: UUID
    let startInventory: Int
    let requiredDrops: Int
}

enum InventoryTargetPlanner {
    // The baseline Depot material sweep covers MATERIAL. Ordinary Fight drops
    // also contain non-inventory counters (for example 5001 reputation).
    static func supportsInventory(classification: String?) -> Bool { classification == "MATERIAL" }

    static func plan(target: InventoryTarget, snapshot: InventorySnapshot?, knownItems: Set<String>) throws -> InventoryTargetPlan {
        guard target.quantity >= 0, target.quantity <= Int(Int32.max), knownItems.contains(target.itemID) else {
            throw InventoryTargetError.invalidTarget
        }
        guard let snapshot, snapshot.items.values.allSatisfy({ $0 >= 0 }) else {
            throw InventoryTargetError.recognitionRequired
        }
        let start = snapshot.items[target.itemID] ?? 0
        return InventoryTargetPlan(generation: snapshot.generation, startInventory: start,
                                   requiredDrops: max(target.quantity - min(start, target.quantity), 0))
    }

    static func validateFrozen(_ plan: InventoryTargetPlan, itemID: String, snapshot: InventorySnapshot?) throws {
        guard let snapshot, snapshot.generation == plan.generation,
              (snapshot.items[itemID] ?? 0) == plan.startInventory else {
            throw InventoryTargetError.stalePreparation
        }
    }

    static func validateQueue(targetIndices: [Int], firstEnabledIndex: Int?) throws {
        guard targetIndices.count <= 1 else { throw InventoryTargetError.multipleTargets }
        // Require the target first: even a reward or unknown task may alter its material.
        if let index = targetIndices.first, index != firstEnabledIndex {
            throw InventoryTargetError.unsafeOrder
        }
    }
}

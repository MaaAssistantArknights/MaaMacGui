//
//  InfrastConfiguration.swift
//  MAA
//
//  Created by hguandl on 16/4/2023.
//

import Foundation

struct InfrastConfiguration: MAATaskConfiguration {
    var type: MAATaskType { .Infrast }

    enum Mode: Int, Codable {
        case `default` = 0
        case custom = 10000
        case rotation = 20000
    }

    enum Facility: String, CaseIterable, Codable {
        case Mfg
        case Trade
        case Power
        case Control
        case Reception
        case Office
        case Dorm
        case Processing
        case Training
    }

    enum DroneUsage: String, CaseIterable, Codable {
        case NotUse = "_NotUse"
        case Money
        case SyntheticJade
        case CombatRecord
        case PureGold
        case OriginStone
        case Chip
    }

    var mode: Mode

    var facility: [Facility]
    var drones: DroneUsage
    var threshold: Double
    var replenish: Bool

    var dorm_notstationed_enabled: Bool
    var dorm_trust_enabled: Bool

    var continue_training: Bool
    var reception_message_board: Bool

    var filename: String
    var plan_index: Int

    // GUI-only parsed state. Keep it stable while a task runs, as in Windows.
    private(set) var customPlan = MAAInfrast.empty
    private(set) var customPlanError: String?

    enum CodingKeys: String, CodingKey {
        case mode, facility, drones, threshold, replenish
        case dorm_notstationed_enabled, dorm_trust_enabled, continue_training, reception_message_board
        case filename, plan_index
    }

    var title: String {
        type.description
    }

    var subtitle: String {
        if mode != .custom {
            return String(localized: "默认换班")
        }

        if customPlanError == nil {
            return customPlan.title ?? filename
        } else {
            return String(localized: "无法识别配置")
        }
    }

    var summary: String {
        if mode != .custom {
            return String(localized: "单设施最优解")
        }

        if plan_index == -1 { return String(localized: "时间轮换") }
        return customPlan.plans.indices.contains(plan_index)
            ? customPlan.name(at: plan_index) : String(localized: "未知排班")
    }

    var projectedTask: MAATask {
        .infrast(self)
    }

    struct Params: Encodable {
        let configuration: InfrastConfiguration

        func encode(to encoder: any Encoder) throws {
            try configuration.execution().configuration.encode(to: encoder)
        }
    }

    var params: Params { Params(configuration: self) }

    func execution(at date: Date = .now, calendar: Calendar = .current) throws
        -> (configuration: Self, selection: MAAInfrast.Selection?)
    {
        guard mode == .custom else { return (self, nil) }
        let selection = try customPlan.select(plan_index, at: date, calendar: calendar)
        var resolved = self
        resolved.plan_index = selection.index
        return (resolved, selection)
    }

    mutating func reloadCustomPlan(resetSelection: Bool = false) {
        loadCustomPlan()
        plan_index = resetSelection ? customPlan.defaultSelection : customPlan.refreshedSelection(plan_index)
    }

    mutating func refreshCustomPlanSelection() {
        plan_index = customPlan.refreshedSelection(plan_index)
    }

    private mutating func loadCustomPlan() {
        customPlan = .empty
        customPlanError = nil
        guard mode == .custom, FileManager.default.fileExists(atPath: filename) else { return }
        do {
            customPlan = try MAAInfrast(path: filename)
        } catch {
            customPlanError = error.localizedDescription
        }
    }

    mutating func restoreCustomPlan() {
        // Windows leaves a missing file's saved selection alone. An existing
        // file that cannot be parsed resets the selection to zero instead.
        guard mode == .custom, !filename.isEmpty, FileManager.default.fileExists(atPath: filename) else { return }
        loadCustomPlan()
        if customPlanError != nil { plan_index = 0 }
        if plan_index < -1 { plan_index = -1 } else if plan_index >= customPlan.plans.count { plan_index = 0 }
    }

    mutating func advanceCustomPlan() {
        guard mode == .custom, let next = customPlan.nextSelection(after: plan_index) else { return }
        plan_index = next
    }
}

extension InfrastConfiguration.Facility: CustomStringConvertible, Identifiable {
    var id: String { rawValue }

    var description: String {
        switch self {
        case .Mfg:
            return String(localized: "制造站")
        case .Trade:
            return String(localized: "贸易站")
        case .Power:
            return String(localized: "发电站")
        case .Control:
            return String(localized: "控制中枢")
        case .Reception:
            return String(localized: "会客室")
        case .Office:
            return String(localized: "办公室")
        case .Dorm:
            return String(localized: "宿舍")
        case .Processing:
            return String(localized: "加工站")
        case .Training:
            return String(localized: "训练室")
        }
    }
}

extension InfrastConfiguration.DroneUsage: CustomStringConvertible {
    var description: String {
        switch self {
        case .NotUse:
            return String(localized: "不使用无人机")
        case .Money:
            return String(localized: "贸易站-龙门币")
        case .SyntheticJade:
            return String(localized: "贸易站-合成玉")
        case .CombatRecord:
            return String(localized: "制造站-经验书")
        case .PureGold:
            return String(localized: "制造站-赤金")
        case .OriginStone:
            return String(localized: "制造站-源石碎片")
        case .Chip:
            return String(localized: "制造站-芯片组")
        }
    }
}

extension InfrastConfiguration {
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.mode = try container.decodeIfPresent(InfrastConfiguration.Mode.self, forKey: .mode) ?? .default
        self.facility =
            try container.decodeIfPresent([InfrastConfiguration.Facility].self, forKey: .facility) ?? [
                .Mfg, .Trade, .Control, .Power, .Reception, .Office, .Dorm, .Processing, .Training,
            ]
        self.drones = try container.decodeIfPresent(InfrastConfiguration.DroneUsage.self, forKey: .drones) ?? .NotUse
        self.threshold = try container.decodeIfPresent(Double.self, forKey: .threshold) ?? 0.3
        self.replenish = try container.decodeIfPresent(Bool.self, forKey: .replenish) ?? false
        self.dorm_notstationed_enabled =
            try container.decodeIfPresent(Bool.self, forKey: .dorm_notstationed_enabled) ?? false
        self.dorm_trust_enabled = try container.decodeIfPresent(Bool.self, forKey: .dorm_trust_enabled) ?? false
        self.filename = try container.decodeIfPresent(String.self, forKey: .filename) ?? ""
        self.plan_index = try container.decodeIfPresent(Int.self, forKey: .plan_index) ?? 0
        self.continue_training = try container.decodeIfPresent(Bool.self, forKey: .continue_training) ?? true
        self.reception_message_board =
            try container.decodeIfPresent(Bool.self, forKey: .reception_message_board) ?? true
        restoreCustomPlan()
    }
}

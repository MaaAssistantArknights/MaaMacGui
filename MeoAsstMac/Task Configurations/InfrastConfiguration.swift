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

    var title: String {
        type.description
    }

    var subtitle: String {
        if mode != .custom {
            return NSLocalizedString("默认换班", comment: "")
        }

        if let plan = try? MAAInfrast(path: filename) {
            return plan.title ?? filename
        } else {
            return NSLocalizedString("无法识别配置", comment: "")
        }
    }

    var summary: String {
        if mode != .custom {
            return NSLocalizedString("单设施最优解", comment: "")
        }

        if let plan = try? MAAInfrast(path: filename), plan_index < plan.plans.count {
            return plan.plans[plan_index].name ?? "\(plan_index)"
        } else {
            return NSLocalizedString("未知排班", comment: "")
        }
    }

    var projectedTask: MAATask {
        .infrast(self)
    }

    typealias Params = Self

    var params: Self {
        self
    }

    private var customPlan: MAAInfrast? {
        guard mode == .custom else { return nil }
        return try? MAAInfrast(path: filename)
    }
}

extension InfrastConfiguration.Facility: CustomStringConvertible, Identifiable {
    var id: String { rawValue }

    var description: String {
        switch self {
        case .Mfg:
            return NSLocalizedString("制造站", comment: "")
        case .Trade:
            return NSLocalizedString("贸易站", comment: "")
        case .Power:
            return NSLocalizedString("发电站", comment: "")
        case .Control:
            return NSLocalizedString("控制中枢", comment: "")
        case .Reception:
            return NSLocalizedString("会客室", comment: "")
        case .Office:
            return NSLocalizedString("办公室", comment: "")
        case .Dorm:
            return NSLocalizedString("宿舍", comment: "")
        case .Processing:
            return NSLocalizedString("加工站", comment: "")
        case .Training:
            return NSLocalizedString("训练室", comment: "")
        }
    }
}

extension InfrastConfiguration.DroneUsage: CustomStringConvertible {
    var description: String {
        switch self {
        case .NotUse:
            return NSLocalizedString("不使用无人机", comment: "")
        case .Money:
            return NSLocalizedString("贸易站-龙门币", comment: "")
        case .SyntheticJade:
            return NSLocalizedString("贸易站-合成玉", comment: "")
        case .CombatRecord:
            return NSLocalizedString("制造站-经验书", comment: "")
        case .PureGold:
            return NSLocalizedString("制造站-赤金", comment: "")
        case .OriginStone:
            return NSLocalizedString("制造站-源石碎片", comment: "")
        case .Chip:
            return NSLocalizedString("制造站-芯片组", comment: "")
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
    }
}

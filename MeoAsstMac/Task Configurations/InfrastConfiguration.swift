//
//  InfrastConfiguration.swift
//  MAA
//
//  Created by hguandl on 16/4/2023.
//

import Foundation

struct InfrastConfiguration: MAATaskConfiguration {
    var enable = true
    var mode = 0

    var facility = MAAInfrastFacility.allCases
    var drones = MAAInfrastDroneUsage.NotUse
    var threshold = 0.3
    var replenish = false

    var dorm_notstationed_enabled = false
    var dorm_trust_enabled = false

    var filename = ""
    var plan_index = 0

    var title: String {
        MAATask.TypeName.Infrast.description
    }

    var subtitle: String {
        if mode != 10000 {
            return NSLocalizedString("默认换班", comment: "")
        }

        if let plan = try? MAAInfrast(path: filename) {
            return plan.title ?? filename
        } else {
            return NSLocalizedString("无法识别配置", comment: "")
        }
    }

    var summary: String {
        if mode != 10000 {
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
        guard mode == 10000 else { return nil }
        return try? MAAInfrast(path: filename)
    }
}

enum MAAInfrastFacility: String, CaseIterable, Codable, CustomStringConvertible, Identifiable {
    case Mfg
    case Trade
    case Power
    case Control
    case Reception
    case Office
    case Dorm

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
        }
    }
}

enum MAAInfrastDroneUsage: String, CaseIterable, Codable, CustomStringConvertible {
    case NotUse = "_NotUse"
    case Money
    case SyntheticJade
    case CombatRecord
    case PureGold
    case OriginStone
    case Chip

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

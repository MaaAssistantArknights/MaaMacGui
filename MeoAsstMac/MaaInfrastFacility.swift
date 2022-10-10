//
//  MaaInfrastFacility.swift
//  MeoAsstMac
//
//  Created by hguandl on 9/10/2022.
//

import Foundation

struct MaaInfrastFacility: Codable {
    let name: Facility
    var enabled: Bool

    enum Facility: String, Codable {
        case Mfg
        case Trade
        case Power
        case Control
        case Reception
        case Office
        case Dorm
    }
    
    static let defaults = [
        MaaInfrastFacility(name: .Mfg, enabled: true),
        MaaInfrastFacility(name: .Trade, enabled: true),
        MaaInfrastFacility(name: .Control, enabled: true),
        MaaInfrastFacility(name: .Power, enabled: true),
        MaaInfrastFacility(name: .Reception, enabled: true),
        MaaInfrastFacility(name: .Office, enabled: true),
        MaaInfrastFacility(name: .Dorm, enabled: true)
    ]
}

extension MaaInfrastFacility: CustomStringConvertible {
    var description: String {
        name.description
    }
}

extension MaaInfrastFacility.Facility: CustomStringConvertible {
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

enum DroneUsage: String, Codable, CaseIterable, CustomStringConvertible {
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

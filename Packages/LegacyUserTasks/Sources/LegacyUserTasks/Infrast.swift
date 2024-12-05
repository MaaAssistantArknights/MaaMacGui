//
//  Infrast.swift
//  LegacyUserTasks
//
//  Created by hguandl on 16/4/2023.
//

import Foundation

@frozen public struct LegacyInfrastConfiguration: Codable {
    public let enable: Bool
    public let mode: Int
    public let facility: [MAALegacyInfrastFacility]
    public let drones: MAALegacyInfrastDroneUsage
    public let threshold: Double
    public let replenish: Bool
    public let dorm_notstationed_enabled: Bool
    public let dorm_trust_enabled: Bool
    public let filename: String
    public let plan_index: Int
}

@frozen public enum MAALegacyInfrastFacility: String, Codable {
    case Mfg
    case Trade
    case Power
    case Control
    case Reception
    case Office
    case Dorm
}

@frozen public enum MAALegacyInfrastDroneUsage: String, Codable {
    case NotUse = "_NotUse"
    case Money
    case SyntheticJade
    case CombatRecord
    case PureGold
    case OriginStone
    case Chip
}

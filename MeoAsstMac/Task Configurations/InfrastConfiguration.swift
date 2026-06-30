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

    enum RotationStyle: String, CaseIterable, Codable {
        case game
        case station_preset
    }

    var mode: Mode
    var rotation_style: RotationStyle

    var facility: [Facility]
    var drones: DroneUsage
    var threshold: Double
    var replenish: Bool

    var dorm_notstationed_enabled: Bool
    var dorm_trust_enabled: Bool

    var continue_training: Bool
    var reception_message_board: Bool
    var reception_receive_clue: Bool
    var reception_clue_exchange: Bool
    var reception_send_clue: Bool

    var filename: String
    var plan_index: Int
    var auto_advance_plan_index: Bool = true

    var preset_layout: StationPresetLayout
    var preset_selected_rooms: [String]
    var preset_rest: Bool
    var station_preset_drones: StationPresetDrones

    var usesCustomJsonPlan: Bool {
        mode == .custom
    }

    var usesRotationStationPreset: Bool {
        mode == .rotation && rotation_style == .station_preset
    }

    var title: String {
        type.description
    }

    var subtitle: String {
        if usesRotationStationPreset {
            return String(localized: "进驻总览设施点预设")
        }

        if usesCustomJsonPlan {
            if let plan = try? MAAInfrast(path: filename) {
                return plan.title ?? filename
            }
            return String(localized: "无法识别配置")
        }

        if mode == .rotation {
            return String(localized: "队列轮换")
        }

        return String(localized: "默认换班")
    }

    var summary: String {
        if usesRotationStationPreset {
            let count = preset_selected_rooms.count
            return String(localized: "设施预设 · \(count) 个设施")
        }

        if usesCustomJsonPlan {
            if let plan = try? MAAInfrast(path: filename), plan_index < plan.plans.count {
                return plan.plans[plan_index].name ?? "\(plan_index)"
            }
            return String(localized: "未知排班")
        }

        if mode == .rotation {
            return String(localized: "游戏内一键轮换")
        }

        return String(localized: "单设施最优解")
    }

    var projectedTask: MAATask {
        .infrast(self)
    }

    typealias Params = InfrastTaskAPIParams

    var params: InfrastTaskAPIParams {
        InfrastTaskAPIParams(configuration: self)
    }

    static func makeForNewTask() -> InfrastConfiguration {
        var config = InfrastConfiguration()
        let layout = StationPresetLayoutStore.lastUsed
        config.preset_layout = layout
        config.preset_selected_rooms = StationPresetRoomList.defaultSelection(for: layout)
        return config
    }

    mutating func syncPresetRoomsAfterLayoutChange() {
        preset_layout.clamp()
        StationPresetLayoutStore.lastUsed = preset_layout
        let pruned = StationPresetRoomList.pruneSelection(preset_selected_rooms, layout: preset_layout)
        if pruned.isEmpty {
            preset_selected_rooms = StationPresetRoomList.defaultSelection(for: preset_layout)
        } else {
            preset_selected_rooms = pruned
        }
    }

    mutating func selectAllPresetRooms() {
        preset_selected_rooms = StationPresetRoomList.rooms(for: preset_layout).map(\.id)
    }

    mutating func clearAllPresetRooms() {
        preset_selected_rooms = []
    }
}

extension InfrastConfiguration.RotationStyle: CustomStringConvertible {
    var description: String {
        switch self {
        case .game:
            return String(localized: "游戏内一键轮换")
        case .station_preset:
            return String(localized: "进驻总览设施点预设")
        }
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
        self.rotation_style =
            try container.decodeIfPresent(InfrastConfiguration.RotationStyle.self, forKey: .rotation_style) ?? .game
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
        self.auto_advance_plan_index = try container.decodeIfPresent(Bool.self, forKey: .auto_advance_plan_index) ?? true
        self.continue_training = try container.decodeIfPresent(Bool.self, forKey: .continue_training) ?? true
        self.reception_message_board =
            try container.decodeIfPresent(Bool.self, forKey: .reception_message_board) ?? true
        self.reception_receive_clue =
            try container.decodeIfPresent(Bool.self, forKey: .reception_receive_clue) ?? true
        self.reception_clue_exchange =
            try container.decodeIfPresent(Bool.self, forKey: .reception_clue_exchange) ?? true
        self.reception_send_clue = try container.decodeIfPresent(Bool.self, forKey: .reception_send_clue) ?? true

        let defaultLayout = StationPresetLayoutStore.lastUsed
        self.preset_layout = try container.decodeIfPresent(StationPresetLayout.self, forKey: .preset_layout) ?? defaultLayout
        self.preset_selected_rooms =
            try container.decodeIfPresent([String].self, forKey: .preset_selected_rooms)
            ?? StationPresetRoomList.defaultSelection(for: preset_layout)
        self.preset_rest = try container.decodeIfPresent(Bool.self, forKey: .preset_rest) ?? true
        self.station_preset_drones =
            try container.decodeIfPresent(StationPresetDrones.self, forKey: .station_preset_drones) ?? .init()
    }
}

extension StationPresetDrones.Room: CustomStringConvertible {
    var description: String {
        switch self {
        case .manufacture:
            return String(localized: "制造站")
        case .trading:
            return String(localized: "贸易站")
        }
    }
}

extension StationPresetDrones.Order: CustomStringConvertible {
    var description: String {
        switch self {
        case .pre:
            return String(localized: "换班前")
        case .post:
            return String(localized: "换班后")
        }
    }
}

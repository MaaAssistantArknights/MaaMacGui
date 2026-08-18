//
//  StationPresetSupport.swift
//  MAA
//

import Foundation

struct StationPresetLayout: Codable, Hashable {
    var mfg_count: Int = 4
    var trade_count: Int = 2
    var power_count: Int = 3

    static let limits = (mfg: 1 ... 5, trade: 1 ... 5, power: 1 ... 3)

    mutating func clamp() {
        mfg_count = min(max(mfg_count, Self.limits.mfg.lowerBound), Self.limits.mfg.upperBound)
        trade_count = min(max(trade_count, Self.limits.trade.lowerBound), Self.limits.trade.upperBound)
        power_count = min(max(power_count, Self.limits.power.lowerBound), Self.limits.power.upperBound)
    }
}

struct StationPresetRoom: Identifiable, Hashable {
    let id: String
    let label: String
}

struct StationPresetDrones: Codable, Hashable {
    var enable: Bool = false
    var room: Room = .manufacture
    var index: Int = 1
    var order: Order = .pre

    enum Room: String, Codable, CaseIterable {
        case manufacture
        case trading
    }

    enum Order: String, Codable, CaseIterable {
        case pre
        case post
    }
}

enum StationPresetRoomList {
    static func rooms(for layout: StationPresetLayout) -> [StationPresetRoom] {
        var list: [StationPresetRoom] = [
            .init(id: "Control", label: String(localized: "控制中枢")),
            .init(id: "Reception", label: String(localized: "会客室")),
        ]
        for index in 1 ... layout.mfg_count {
            list.append(.init(id: "Mfg\(index)", label: String(localized: "制造站\(index)")))
        }
        for index in 1 ... layout.trade_count {
            list.append(.init(id: "Trade\(index)", label: String(localized: "贸易站\(index)")))
        }
        for index in 1 ... layout.power_count {
            list.append(.init(id: "Power\(index)", label: String(localized: "发电站\(index)")))
        }
        list.append(.init(id: "Office", label: String(localized: "办公室")))
        return list
    }

    static func defaultSelection(for layout: StationPresetLayout) -> [String] {
        rooms(for: layout).map(\.id)
    }

    static func pruneSelection(_ selection: [String], layout: StationPresetLayout) -> [String] {
        let valid = Set(rooms(for: layout).map(\.id))
        return selection.filter { valid.contains($0) }
    }
}

enum StationPresetLayoutStore {
    private static let key = "station_preset_last_layout"

    static var lastUsed: StationPresetLayout {
        get {
            guard let data = UserDefaults.standard.data(forKey: key) else {
                return StationPresetLayout()
            }
            guard var stored = try? JSONDecoder().decode(StationPresetLayout.self, from: data) else {
                return StationPresetLayout()
            }
            stored.clamp()
            return stored
        }
        set {
            var layout = newValue
            layout.clamp()
            if let data = try? JSONEncoder().encode(layout) {
                UserDefaults.standard.set(data, forKey: key)
            }
        }
    }
}

struct InfrastTaskAPIParams: Encodable {
    let enable = true
    let mode: Int
    let rotation_style: String?
    let facility: [String]
    let threshold: Double
    let replenish: Bool
    let dorm_notstationed_enabled: Bool
    let dorm_trust_enabled: Bool
    let continue_training: Bool
    let reception_message_board: Bool
    let reception_receive_clue: Bool
    let reception_clue_exchange: Bool
    let reception_send_clue: Bool
    let filename: String?
    let plan_index: Int?
    let preset: PresetPayload?
    let drones: DronesPayload?

    private let normalDrones: String?

    struct PresetPayload: Encodable {
        let rooms: [String]
        let rest: Bool
    }

    struct DronesPayload: Encodable {
        let enable: Bool
        let room: String
        let index: Int
        let order: String
    }

    init(configuration: InfrastConfiguration) {
        mode = configuration.mode.rawValue
        rotation_style = configuration.mode == .rotation ? configuration.rotation_style.rawValue : nil
        threshold = configuration.threshold
        replenish = configuration.replenish
        dorm_notstationed_enabled = configuration.dorm_notstationed_enabled
        dorm_trust_enabled = configuration.dorm_trust_enabled
        continue_training = configuration.continue_training
        reception_message_board = configuration.reception_message_board
        reception_receive_clue = configuration.reception_receive_clue
        reception_clue_exchange = configuration.reception_clue_exchange
        reception_send_clue = configuration.reception_send_clue

        if configuration.usesRotationStationPreset {
            facility = ["Mfg"]
            filename = nil
            plan_index = nil
            preset = .init(
                rooms: configuration.preset_selected_rooms,
                rest: configuration.preset_rest
            )
            if configuration.station_preset_drones.enable {
                drones = .init(
                    enable: true,
                    room: configuration.station_preset_drones.room.rawValue,
                    index: configuration.station_preset_drones.index,
                    order: configuration.station_preset_drones.order.rawValue
                )
            } else {
                drones = nil
            }
            normalDrones = nil
        } else if configuration.mode == .custom {
            facility = configuration.facility.map(\.rawValue)
            filename = configuration.filename
            plan_index = configuration.plan_index
            preset = nil
            drones = nil
            normalDrones = nil
        } else {
            facility = configuration.facility.map(\.rawValue)
            filename = nil
            plan_index = nil
            preset = nil
            drones = nil
            normalDrones = configuration.drones.rawValue
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(enable, forKey: .enable)
        try container.encode(mode, forKey: .mode)
        if let rotation_style {
            try container.encode(rotation_style, forKey: .rotation_style)
        }
        try container.encode(facility, forKey: .facility)
        try container.encode(threshold, forKey: .threshold)
        try container.encode(replenish, forKey: .replenish)
        try container.encode(dorm_notstationed_enabled, forKey: .dorm_notstationed_enabled)
        try container.encode(dorm_trust_enabled, forKey: .dorm_trust_enabled)
        try container.encode(continue_training, forKey: .continue_training)
        try container.encode(reception_message_board, forKey: .reception_message_board)
        try container.encode(reception_receive_clue, forKey: .reception_receive_clue)
        try container.encode(reception_clue_exchange, forKey: .reception_clue_exchange)
        try container.encode(reception_send_clue, forKey: .reception_send_clue)

        if let filename {
            try container.encode(filename, forKey: .filename)
        }
        if let plan_index {
            try container.encode(plan_index, forKey: .plan_index)
        }
        if let preset {
            try container.encode(preset, forKey: .preset)
        }

        if let drones {
            try container.encode(drones, forKey: .drones)
        } else if let normalDrones {
            try container.encode(normalDrones, forKey: .drones)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case enable
        case mode
        case rotation_style
        case facility
        case threshold
        case replenish
        case dorm_notstationed_enabled
        case dorm_trust_enabled
        case continue_training
        case reception_message_board
        case reception_receive_clue
        case reception_clue_exchange
        case reception_send_clue
        case filename
        case plan_index
        case preset
        case drones
    }
}

//
//  DepotMaintainConfiguration.swift
//  MAA
//

import Foundation

struct DepotMaintainConfiguration: MAATaskConfiguration {
    var type: MAATaskType { .DepotMaintain }

    var plans: [Plan]
    var updateDepot: Bool
    var useAutoSeries: Bool
    var enableMedicine: Bool
    var enableStone: Bool
    var useExpiringMedicine: Bool
    var skipDuringActivity: Bool
    var skipDuringResourceCollection: Bool

    var title: String { String(localized: "库存保持") }

    var subtitle: String {
        String(localized: "\(plans.count) 条计划")
    }

    var summary: String {
        plans.prefix(2).map(\.stage).filter { !$0.isEmpty }.joined(separator: ", ")
    }

    var projectedTask: MAATask { .depotMaintain(self) }

    typealias Params = Self
    var params: Self { self }

    struct Plan: Codable, Hashable, Identifiable {
        var id: UUID
        var stage: String
        var dropID: String
        var target: Int
        var useMedicine: Bool
        var medicineCount: Int
        var useStone: Bool
        var stoneCount: Int

        init(
            id: UUID = UUID(),
            stage: String = "",
            dropID: String = "",
            target: Int = 0,
            useMedicine: Bool = false,
            medicineCount: Int = 0,
            useStone: Bool = false,
            stoneCount: Int = 0
        ) {
            self.id = id
            self.stage = stage
            self.dropID = dropID
            self.target = target
            self.useMedicine = useMedicine
            self.medicineCount = medicineCount
            self.useStone = useStone
            self.stoneCount = stoneCount
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
            stage = try container.decodeIfPresent(String.self, forKey: .stage) ?? ""
            dropID = try container.decodeIfPresent(String.self, forKey: .dropID) ?? ""
            target = try container.decodeIfPresent(Int.self, forKey: .target) ?? 0
            useMedicine = try container.decodeIfPresent(Bool.self, forKey: .useMedicine) ?? false
            medicineCount = try container.decodeIfPresent(Int.self, forKey: .medicineCount) ?? 0
            useStone = try container.decodeIfPresent(Bool.self, forKey: .useStone) ?? false
            stoneCount = try container.decodeIfPresent(Int.self, forKey: .stoneCount) ?? 0
        }
    }
}

extension DepotMaintainConfiguration {
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        plans = try container.decodeIfPresent([Plan].self, forKey: .plans) ?? []
        updateDepot = try container.decodeIfPresent(Bool.self, forKey: .updateDepot) ?? true
        useAutoSeries = try container.decodeIfPresent(Bool.self, forKey: .useAutoSeries) ?? false
        enableMedicine = try container.decodeIfPresent(Bool.self, forKey: .enableMedicine) ?? true
        enableStone = try container.decodeIfPresent(Bool.self, forKey: .enableStone) ?? true
        useExpiringMedicine = try container.decodeIfPresent(Bool.self, forKey: .useExpiringMedicine) ?? false
        skipDuringActivity = try container.decodeIfPresent(Bool.self, forKey: .skipDuringActivity) ?? false
        skipDuringResourceCollection =
            try container.decodeIfPresent(Bool.self, forKey: .skipDuringResourceCollection) ?? false
    }
}

extension DepotMaintainConfiguration {
    enum Preset: String, CaseIterable, Identifiable {
        case chip1
        case chip2
        case lmd
        case certificate
        case skillSummary

        var id: String { rawValue }

        var title: String {
            switch self {
            case .chip1: String(localized: "低级芯片（全职业）")
            case .chip2: String(localized: "高级芯片组（全职业）")
            case .lmd: String(localized: "龙门币")
            case .certificate: String(localized: "采购凭证（红票）")
            case .skillSummary: String(localized: "技巧概要·卷3")
            }
        }

        var plans: [Plan] {
            switch self {
            case .chip1:
                return Self.chipPlans(level: 1, target: 20)
            case .chip2:
                return Self.chipPlans(level: 2, target: 20)
            case .lmd:
                return [.init(stage: "CE-6", dropID: "4001", target: 2_000_000)]
            case .certificate:
                return [.init(stage: "AP-5", dropID: "4006", target: 5_000)]
            case .skillSummary:
                return [.init(stage: "CA-5", dropID: "3303", target: 200)]
            }
        }

        private static func chipPlans(level: Int, target: Int) -> [Plan] {
            let entries: [(String, [String])] = [
                ("PR-A-\(level)", level == 1 ? ["3261", "3231"] : ["3262", "3232"]),
                ("PR-B-\(level)", level == 1 ? ["3251", "3241"] : ["3252", "3242"]),
                ("PR-C-\(level)", level == 1 ? ["3211", "3271"] : ["3212", "3272"]),
                ("PR-D-\(level)", level == 1 ? ["3221", "3281"] : ["3222", "3282"]),
            ]
            return entries.flatMap { stage, drops in
                drops.map { Plan(stage: stage, dropID: $0, target: target) }
            }
        }
    }
}

struct DepotMaintainFightParameters: Encodable {
    let stage: String
    let medicine: Int
    let medicineExpireDays: Int
    let stone: Int
    let times: Int
    let series: Int
    let drops: [String: Int]
    let reportToPenguin = false
    let penguinID = ""
    let server: String
    let clientType: String
    let drGrandet = false

    private enum CodingKeys: String, CodingKey {
        case stage
        case medicine
        case medicineExpireDays = "medicine_expire_days"
        case stone
        case times
        case series
        case drops
        case reportToPenguin = "report_to_penguin"
        case penguinID = "penguin_id"
        case server
        case clientType = "client_type"
        case drGrandet = "DrGrandet"
    }
}

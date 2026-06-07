//
//  FightConfiguration.swift
//  MAA
//
//  Created by hguandl on 16/4/2023.
//

import Foundation

struct WeeklySchedule: Codable, Equatable, Hashable {
    var sunday: Bool = true
    var monday: Bool = true
    var tuesday: Bool = true
    var wednesday: Bool = true
    var thursday: Bool = true
    var friday: Bool = true
    var saturday: Bool = true

    func isEnabled(for weekday: Int) -> Bool {
        switch weekday {
        case 1: return sunday
        case 2: return monday
        case 3: return tuesday
        case 4: return wednesday
        case 5: return thursday
        case 6: return friday
        case 7: return saturday
        default: return true
        }
    }

    subscript(_ index: Int) -> Bool {
        get { isEnabled(for: index) }
        set {
            switch index {
            case 1: sunday = newValue
            case 2: monday = newValue
            case 3: tuesday = newValue
            case 4: wednesday = newValue
            case 5: thursday = newValue
            case 6: friday = newValue
            case 7: saturday = newValue
            default: break
            }
        }
    }
}

struct FightConfiguration: MAATaskConfiguration {
    var type: MAATaskType { .Fight }

    var stage: String
    var medicine: Int?
    var expiring_medicine: Int?
    var stone: Int?
    var times: Int?
    var series: Int?
    var drops: [String: Int]?

    var report_to_penguin: Bool
    var penguin_id: String
    var server: String
    var client_type: String
    var DrGrandet: Bool

    var useWeeklySchedule: Bool
    var weeklySchedule: WeeklySchedule

    var title: String {
        type.description
    }

    var subtitle: String {
        if stage == "" {
            return String(localized: "当前/上次")
        } else {
            return stage
        }
    }

    var summary: String {
        var parts = [String]()

        if let medicine {
            parts.append(String(localized: "理智药") + "\(medicine)")
        }

        if let stone {
            parts.append(String(localized: "源石") + "\(stone)")
        }

        if let times {
            parts.append("\(times)" + String(localized: "次"))
        }

        return parts.joined(separator: ";")
    }

    var projectedTask: MAATask {
        .fight(self)
    }

    typealias Params = Self

    var params: Self {
        self
    }

    // 掉落物品列表
    static var dropItems: [(id: String, item: DropItem)] = []
    static var id2index: [String: Int] = [:]  // (id -> idx of dropItems)
    static let _excludedValues = Set([
        3213, 3223, 3233, 3243,  // 双芯片
        3253, 3263, 3273, 3283,  // 双芯片
        7001, 7002, 7003, 7004,  // 许可
        6001,  // 演习卷
        4004, 4005,  // 凭证
        3141, 4002,  // 源石
        32001,  // 芯片助剂
        30115,  // 聚合剂
        30125,  // 双极纳米片
        30135,  // D32钢
        30145,  // 晶体电子单元
        30155,  // 烧结核凝晶
    ])

    static func initDropItems(_ language: String) throws {
        if !dropItems.isEmpty { return }
        let local: String? =
            switch language {
            case "zh-tw": "txwy"
            case "en-us": "YoStarEN"
            case "ja-jp": "YoStarJP"
            case "ko-kr": "YoStarKR"
            default: nil
            }
        let url_base = Bundle.main.resourceURL!
            .appendingPathComponent("resource")
        let url_mid =
            if let local {
                url_base.appendingPathComponent("global")
                    .appendingPathComponent(local)
                    .appendingPathComponent("resource")
            } else {
                url_base
            }
        let url = url_mid.appendingPathComponent("item_index.json")
        let data = try Data(contentsOf: url)
        let json = try JSONDecoder().decode([String: DropItem].self, from: data)
        for item in json {
            guard let k = Int(item.key) else { continue }
            guard !_excludedValues.contains(k) else { continue }
            dropItems.append((id: item.key, item: item.value))
        }
        dropItems.sort { $0.1.name.localizedCompare($1.1.name) == .orderedAscending }
        for (idx, item) in dropItems.enumerated() {
            id2index[item.0] = idx
        }
    }
}

struct DropItem: Codable, Equatable {
    let classifyType: String?
    let description: String?
    let icon: String
    let name: String
    let sortId: Int
    let usage: String?
}

extension FightConfiguration {
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.stage = try container.decodeIfPresent(String.self, forKey: .stage) ?? ""
        self.medicine = try container.decodeIfPresent(Int.self, forKey: .medicine)
        self.expiring_medicine = try container.decodeIfPresent(Int.self, forKey: .expiring_medicine)
        self.stone = try container.decodeIfPresent(Int.self, forKey: .stone)
        self.times = try container.decodeIfPresent(Int.self, forKey: .times)
        self.series = try container.decodeIfPresent(Int.self, forKey: .series)
        self.drops = try container.decodeIfPresent([String: Int].self, forKey: .drops)
        self.report_to_penguin = try container.decodeIfPresent(Bool.self, forKey: .report_to_penguin) ?? false
        self.penguin_id = try container.decodeIfPresent(String.self, forKey: .penguin_id) ?? ""
        self.server = try container.decodeIfPresent(String.self, forKey: .server) ?? "CN"
        self.client_type = try container.decodeIfPresent(String.self, forKey: .client_type) ?? ""
        self.DrGrandet = try container.decodeIfPresent(Bool.self, forKey: .DrGrandet) ?? false
        self.useWeeklySchedule = try container.decodeIfPresent(Bool.self, forKey: .useWeeklySchedule) ?? false
        self.weeklySchedule = try container.decodeIfPresent(WeeklySchedule.self, forKey: .weeklySchedule) ?? WeeklySchedule()
    }
}

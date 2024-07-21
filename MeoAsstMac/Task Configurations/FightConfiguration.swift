//
//  FightConfiguration.swift
//  MAA
//
//  Created by hguandl on 16/4/2023.
//

import Foundation

struct FightConfiguration: MAATaskConfiguration {
    var enable = true
    var stage = ""
    var medicine: Int?
    var expiring_medicine: Int?
    var stone: Int?
    var times: Int?
    var series: Int?
    var drops: [String: Int]?

    var report_to_penguin = false
    var penguin_id = ""
    var server = "CN"
    var client_type = ""
    var DrGrandet = false

    var title: String {
        MAATask.TypeName.Fight.description
    }

    var subtitle: String {
        if stage == "" {
            return NSLocalizedString("当前/上次", comment: "")
        } else {
            return stage
        }
    }

    var summary: String {
        var parts = [String]()

        if let medicine {
            parts.append(NSLocalizedString("理智药", comment: "") + "\(medicine)")
        }

        if let stone {
            parts.append(NSLocalizedString("源石", comment: "") + "\(stone)")
        }

        if let times {
            parts.append("\(times)" + NSLocalizedString("次", comment: ""))
        }

        return parts.joined(separator: ";")
    }

    // 掉落物品列表
    static var dropItems: [(id: String, item: DropItem)] = []
    static var id2index: [String: Int] = [:] // (id -> idx of dropItems)
    static let _excludedValues = Set([
        3213, 3223, 3233, 3243, // 双芯片
        3253, 3263, 3273, 3283, // 双芯片
        7001, 7002, 7003, 7004, // 许可
        6001, // 演习卷
        4004, 4005, // 凭证
        3141, 4002, // 源石
        32001, // 芯片助剂
        30115, // 聚合剂
        30125, // 双极纳米片
        30135, // D32钢
        30145, // 晶体电子单元
        30155, // 烧结核凝晶
    ])

    static func initDropItems(_ language: String) throws {
        if !dropItems.isEmpty { return }
        let local: String? = switch language {
        case "zh-tw": "txwy"
        case "en-us": "YoStarEN"
        case "ja-jp": "YoStarJP"
        case "ko-kr": "YoStarKR"
        default: nil
        }
        let url_base = Bundle.main.resourceURL!
            .appendingPathComponent("resource")
        let url_mid = if let local {
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

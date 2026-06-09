//
//  ReclamationConfiguration.swift
//  MAA
//
//  Created by hguandl on 19/4/2023.
//

import Foundation

struct ReclamationConfiguration: MAATaskConfiguration {
    var type: MAATaskType { .Reclamation }

    var theme: ReclamationTheme
    var mode: Int
    var tools_to_craft: [String]
    var increment_mode: Int
    var num_craft_batches: Int

    var modes: [Int: String] {
        switch theme {
        case .fire:
            return [
                0: String(localized: "刷分与建造点"),
                1: String(localized: "刷赤金"),
            ]
        case .tales:
            return [
                0: String(localized: "无存档，通过进出关卡刷生息点数"),
                1: String(localized: "有存档，通过组装支援道具刷生息点数，组装完成后将会跳到下一个量定日并读取前一个量定日的存档"),
            ]
        case .relaunch:
            return [
                1 << 4: String(localized: "RA-1"),
                2 << 4: String(localized: "RA-15"),
                3 << 4: String(localized: "RA-4"),
            ]
        }
    }

    var tip: String? {
        guard theme == .relaunch else { return nil }

        switch mode {
        case 1 << 4:
            return """
                收益参考：每把约 159 代币 + 统筹点数，单轮耗时约 2 分 10 秒

                干员要求：无

                前置步骤：推进主线至 RA-1 已通关状态

                在大地图打开 RA-1，右下角出现“开启建设”时启动任务，即可自动循环

                注意：如果已解锁开局额外携带物品的相关科技，请将基地内会导致开局额外携带物品的设施拆除，如食品供给站、饮品供给站、兽栏等

                任务流程：自动执行精耕细作、建设、交付资源、结算循环
                """
        case 2 << 4:
            return """
                收益参考：每把约 500 代币 + 统筹点数，单轮耗时约 3 分钟

                干员要求：圣聆初雪（可以借助战）

                前置步骤：
                1.推进主线至 RA-15 已通关状态
                2.如果自己有圣聆初雪，请手动打开关卡并配队一次，保证为五先锋（无练度要求）+ 初雪，且初雪位于六号位即最后一个选的人，然后保存配队并退出关卡
                3.如果使用助战圣聆初雪，请保证圣聆初雪在术士助战首页（考虑挚友）

                在大地图打开 RA-15，右下角出现「开启建设」时启动任务，即可自动循环

                注意：如果已解锁开局额外携带物品的相关科技，请将基地内会导致开局额外携带物品的设施拆除，如食品供给站、饮品供给站、兽栏等

                任务流程：用圣聆初雪完成 60 杀任务
                """
        case 3 << 4:
            return """
                收益参考：每把约 417 代币 + 统筹点数，单轮耗时约 1 分 40 秒

                干员要求：维什戴尔（可以借助战）

                前置步骤：
                1.推进主线至 RA-4 已通关状态
                2.解锁策略筹划经营
                3.如果自己有维什戴尔，请手动打开关卡并配队一次，保证为任意 5 个费用比维什戴尔低的干员+ 维什戴尔，且维什戴尔位于六号位即最后一个选的人，然后确认招募，放弃本次建设并在开始建设处开始
                4.如果使用助战维什戴尔，请保证维什戴尔在狙击助战首页（考虑挚友），请手动打开关卡编入任意 5 个费用比维什戴尔低的干员，六号位选择维什戴尔助战后确认招募，放弃本次建设并在开始建设处开始（保证队伍前五位有人且六号位为空）

                在大地图打开 RA-4，右下角出现「开启建设」时启动任务，即可自动循环

                注意：如果已解锁开局额外携带物品的相关科技，请将基地内会导致开局额外携带物品的设施拆除，如食品供给站、饮品供给站、兽栏等

                任务流程：使用筹划经营策略给予的赤金解锁区域，使用维什戴尔完成击杀 boss 任务
                """
        default:
            return nil
        }
    }

    var increment_modes: [Int: String] {
        return [
            0: String(localized: "点击加号按钮"),
            1: String(localized: "按住加号按钮"),
        ]
    }

    var toolsToCraftEnabled: Bool {
        theme == .tales && mode == 1
    }

    var title: String {
        type.description
    }

    var subtitle: String {
        theme.description
    }

    var summary: String {
        modes[mode] ?? ""
    }

    var projectedTask: MAATask {
        .reclamation(self)
    }

    typealias Params = Self

    var params: Self {
        self
    }
}

extension ReclamationConfiguration {
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.theme = try container.decodeIfPresent(ReclamationTheme.self, forKey: .theme) ?? .tales
        let rawMode = try container.decodeIfPresent(Int.self, forKey: .mode) ?? 0
        self.tools_to_craft = try container.decodeIfPresent([String].self, forKey: .tools_to_craft) ?? ["荧光棒"]
        self.increment_mode = try container.decodeIfPresent(Int.self, forKey: .increment_mode) ?? 0
        self.num_craft_batches = try container.decodeIfPresent(Int.self, forKey: .num_craft_batches) ?? 16

        if self.theme == .relaunch && rawMode < 1 << 4 {
            self.mode = rawMode == 1 ? (2 << 4) : (1 << 4)
        } else {
            self.mode = rawMode
        }
    }
}

enum ReclamationTheme: String, CaseIterable, Codable, CustomStringConvertible {
    case fire = "Fire"
    case tales = "Tales"
    case relaunch = "RelaunchAnchor"

    var description: String {
        switch self {
        case .fire:
            return String(localized: "沙中之火")
        case .tales:
            return String(localized: "沙洲遗闻")
        case .relaunch:
            return String(localized: "重启锚点")
        }
    }
}

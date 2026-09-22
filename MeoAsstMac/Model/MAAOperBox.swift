//
//  MAAOperBox.swift
//  MAA
//
//  Created by hguandl on 22/4/2023.
//

import Foundation
import JBird
import OSLog
import SwiftUI

private let logger = Logger(subsystem: "com.hguandl.MeoAsstMac", category: "MAAOperBox")

@JSONRepresentable struct MAAOperBox: Hashable {
    let done: Bool
    let all_opers: [Oper]
    let own_opers: [OwnedOper]

    /// 识别数据来源（local 或 yituliu），仅一图流 OpenAPI 获取的数据有值
    let source: String?

    @JSONRepresentable struct Oper: Identifiable, Hashable {
        let id: String
        let own: Bool
        let name: String
        let rarity: Int
    }

    @JSONRepresentable struct OwnedOper: Identifiable, Hashable {
        let id: String
        let own: Bool
        let name: String
        let rarity: Int

        let elite: Int
        let level: Int
        let potential: Int

        /// 当前主技能等级（1~7），仅一图流 OpenAPI 获取的数据有值
        let mainSkillLevel: Int?
        /// 技能专精，仅一图流 OpenAPI 获取的数据有值
        let skills: [Skill]?
        /// 模组，仅一图流 OpenAPI 获取的数据有值
        let equips: [Equip]?
    }

    /// 技能专精数据
    @JSONRepresentable struct Skill: Hashable {
        let id: String
        let level: Int
    }

    /// 模组数据
    @JSONRepresentable struct Equip: Hashable {
        let id: String
        let type: String?
        let level: Int
    }
}

extension MAAOperBox.OwnedOper: Comparable {
    static func < (lhs: MAAOperBox.OwnedOper, rhs: MAAOperBox.OwnedOper) -> Bool {
        for predicate in sortPredicates {
            switch (predicate(lhs, rhs), predicate(rhs, lhs)) {
            case (true, _):
                return true
            case (_, true):
                return false
            case (false, false):
                break
            }
        }
        return false
    }

    private static let sortPredicates: [@Sendable (Self, Self) -> Bool] = [
        { $0.elite > $1.elite },
        { $0.level > $1.level },
        { $0.rarity > $1.rarity },
        { $0.id < $1.id },
    ]
}

extension MAAOperBox.OwnedOper {
    @ViewBuilder var label: some View {
        HStack(spacing: 20) {
            Text(name)
            Text("精英\(elite) Lv\(level) 潜能\(potential)")
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: 一图流 OpenAPI

/// `@JSONRepresentable` 由宏生成构造器，成员逐一构造时用显式初始化器补齐
extension MAAOperBox {
    init(done: Bool, all_opers: [Oper], own_opers: [OwnedOper], source: String?) {
        self.done = done
        self.all_opers = all_opers
        self.own_opers = own_opers
        self.source = source
    }
}

extension MAAOperBox.Oper {
    init(id: String, own: Bool, name: String, rarity: Int) {
        self.id = id
        self.own = own
        self.name = name
        self.rarity = rarity
    }
}

extension MAAOperBox.OwnedOper {
    init(
        id: String, own: Bool, name: String, rarity: Int, elite: Int, level: Int, potential: Int,
        mainSkillLevel: Int? = nil, skills: [MAAOperBox.Skill]? = nil, equips: [MAAOperBox.Equip]? = nil
    ) {
        self.id = id
        self.own = own
        self.name = name
        self.rarity = rarity
        self.elite = elite
        self.level = level
        self.potential = potential
        self.mainSkillLevel = mainSkillLevel
        self.skills = skills
        self.equips = equips
    }
}

extension MAAOperBox.Skill {
    init(id: String, level: Int) {
        self.id = id
        self.level = level
    }
}

extension MAAOperBox.Equip {
    init(id: String, type: String?, level: Int) {
        self.id = id
        self.type = type
        self.level = level
    }
}

extension MAAOperBox {
    /// 用本地干员表补齐一图流 OpenAPI 数据缺少的名称与星级，构造与 core 干员识别结果等价的模型。
    ///
    /// 本地资源过旧、表里查不到的干员跳过；已拥有干员按升变形态归一为基础形态。
    init(yituliu data: [YituliuApiService.OperatorInfo], channel: MAAClientChannel) {
        let table = LocalOperatorTable.shared
        let language = LocalOperatorTable.currentLanguage

        var ownIDs = Set<String>()
        var ownOpers = [OwnedOper]()
        for info in data {
            let id = Self.canonicalID(of: info.id)
            guard let entry = table[id] else {
                logger.info("Skipped unknown operator from yituliu open-api: \(info.id)")
                continue
            }
            guard ownIDs.insert(id).inserted else {
                continue
            }

            ownOpers.append(
                OwnedOper(
                    id: id, own: true, name: entry.name(for: language), rarity: entry.rarity,
                    elite: info.evolvePhase ?? 0, level: info.level ?? 0, potential: info.potentialRank ?? 0,
                    mainSkillLevel: info.mainSkillLevel,
                    skills: info.skills?.map { Skill(id: $0.id, level: $0.level) },
                    equips: info.equips?.map { Equip(id: $0.id, type: $0.type, level: $0.level) }
                ))
        }

        let allOpers =
            table
            .filter { $0.value.isOperator && $0.value.isAvailable(in: channel) }
            .map { id, entry in
                Oper(id: id, own: ownIDs.contains(id), name: entry.name(for: language), rarity: entry.rarity)
            }
            .sorted {
                if $0.rarity != $1.rarity {
                    return $0.rarity > $1.rarity
                }
                return $0.id < $1.id
            }

        self.init(done: true, all_opers: allOpers, own_opers: ownOpers, source: "yituliu")
    }

    /// 本地干员表（`resource/battle_data.json`）是否加载成功。
    ///
    /// 加载失败时一图流数据无法补齐名称与星级，全部干员会被跳过，与账号本身没有练度数据是两回事。
    static var hasLocalOperatorTable: Bool {
        !LocalOperatorTable.shared.isEmpty
    }

    /// 升变形态 ID 到基础形态 ID 的等价表（对齐 WPF `DataHelper.GetCanonicalOperId`）
    private static let promotedOperIDs = [
        "char_1001_amiya2": "char_002_amiya",
        "char_1037_amiya3": "char_002_amiya",
    ]

    /// 升变形态归一为基础形态，后续展示与去重都使用归一后的 ID
    private static func canonicalID(of id: String) -> String {
        promotedOperIDs[id] ?? id
    }
}

/// `resource/battle_data.json` 的干员条目，只取补齐名称与星级所需的字段
private struct OperatorEntry: Decodable {
    let name: String
    let nameEn: String?
    let nameJp: String?
    let nameKr: String?
    let nameTw: String?
    let rarity: Int
    let profession: String
    let nameEnUnavailable: Bool?
    let nameJpUnavailable: Bool?
    let nameKrUnavailable: Bool?
    let nameTwUnavailable: Bool?

    /// 可培养干员，battle_data 里还有大量 TRAP（装置）与 TOKEN（召唤物）
    static let professions: Set<String> = [
        "PIONEER", "WARRIOR", "SNIPER", "TANK", "MEDIC", "SUPPORT", "CASTER", "SPECIAL",
    ]

    var isOperator: Bool {
        Self.professions.contains(profession)
    }

    /// 干员在指定客户端中是否可用（对齐 WPF `DataHelper.IsCharacterAvailableInClient`）
    func isAvailable(in channel: MAAClientChannel) -> Bool {
        switch channel {
        case .Official, .Bilibili:
            return true
        case .txwy:
            return nameTwUnavailable != true
        case .YoStarEN:
            return nameEnUnavailable != true
        case .YoStarJP:
            return nameJpUnavailable != true
        case .YoStarKR:
            return nameKrUnavailable != true
        }
    }

    /// 按界面语言取干员名，取不到时退回中文名（对齐 WPF `DataHelper.GetLocalizedCharacterName`）
    func name(for language: String) -> String {
        switch language {
        case "en":
            return nameEn ?? name
        case "ko":
            return nameKr ?? name
        case "zh-Hant":
            return nameTw ?? name
        default:
            return name
        }
    }
}

/// 本地干员表，来源为 core 资源 `resource/battle_data.json` 的 `chars`
private enum LocalOperatorTable {
    static let shared: [String: OperatorEntry] = load()

    /// 干员名语言跟随 App 当前语言
    static var currentLanguage: String {
        Bundle.main.preferredLocalizations.first ?? "zh-Hans"
    }

    private static func load() -> [String: OperatorEntry] {
        guard let url else {
            logger.error("battle_data.json not found")
            return [:]
        }

        struct BattleData: Decodable {
            let chars: [String: OperatorEntry]
        }

        do {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            return try decoder.decode(BattleData.self, from: Data(contentsOf: url)).chars
        } catch {
            logger.error("Failed to load battle_data.json: \(error)")
            return [:]
        }
    }

    /// 用户更新过的外部资源优先，与 core 加载资源的顺序一致
    private static var url: URL? {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let external = documents.appendingPathComponent("resource/battle_data.json")
        if FileManager.default.fileExists(atPath: external.path) {
            return external
        }
        return Bundle.main.resourceURL?.appendingPathComponent("resource/battle_data.json")
    }
}

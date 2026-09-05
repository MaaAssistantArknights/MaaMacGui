//
//  MAAOperBox.swift
//  MAA
//
//  Created by hguandl on 22/4/2023.
//

import SwiftUI

struct MAAOperBox: Codable, Hashable {
    let done: Bool
    let all_opers: [Oper]
    let own_opers: [OwnedOper]

    struct Oper: Codable, Hashable {
        let id: String
        let own: Bool
        let name: String
        let rarity: Int
    }

    struct OwnedOper: Codable, Hashable {
        let id: String
        let own: Bool
        let name: String
        let rarity: Int

        let elite: Int
        let level: Int
        let potential: Int
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

// MARK: - Export

extension MAAOperBox {
    /// 与 Windows 版“干员列表 JSON 导出”单条记录同构，键序即 Json.NET 的输出顺序。
    struct ExportItem: Hashable {
        let id: String
        let name: String
        let elite: Int
        let level: Int
        let own: Bool
        let potential: Int
        let rarity: Int
    }

    /// 与 Windows `DataHelper._virtualOperators` 对齐的未实装/试用干员 charId，
    /// 这些干员不出现在导出 JSON 中（Windows 遍历其全量干员表时本就轮不到它们）。
    private static let excludedExportIDs: Set<String> = [
        "char_504_rguard", "char_505_rcast", "char_506_rmedic", "char_507_rsnipe",
        "char_508_aguard", "char_509_acast", "char_510_amedic", "char_511_asnipe",
        "char_512_aprot", "char_513_apionr", "char_514_rdfend",
        "char_600_cpione", "char_601_cguard", "char_602_cdfend", "char_603_csnipe",
        "char_604_ccast", "char_605_cmedic", "char_606_csuppo", "char_607_cspec",
        "char_608_acpion", "char_609_acguad", "char_610_acfend", "char_611_acnipe",
        "char_612_accast", "char_613_acmedc", "char_614_acsupo", "char_615_acspec",
        "char_616_pithst", "char_617_sharp2",
        "char_1001_amiya2", "char_1037_amiya3",
    ]

    /// 以 `all_opers` 为全量（保持其顺序），按 `id` 合并 `own_opers` 的精装/等级/潜能。
    /// 未匹配到的干员按未拥有导出（`elite/level/potential` 为 0，`own` 为 false）。
    /// 只输出 `all_opers` 中存在且非 `excludedExportIDs` 的干员，与 Windows 遍历其全量干员表的语义一致。
    var exportItems: [ExportItem] {
        let ownByID = Dictionary(own_opers.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return all_opers
            .filter { !Self.excludedExportIDs.contains($0.id) }
            .map { oper in
            let owned = ownByID[oper.id]
            return ExportItem(
                id: oper.id,
                name: oper.name,
                elite: owned?.elite ?? 0,
                level: owned?.level ?? 0,
                own: owned?.own ?? false,
                potential: owned?.potential ?? 0,
                rarity: oper.rarity)
        }
    }

    /// 缩进 JSON（UTF-8、无 BOM），剪贴板与文件正文共用此内容。
    /// JSONEncoder 不保证键序，故手写序列化以匹配 Windows 的 `id,name,elite,level,own,potential,rarity` 顺序与 2 空格缩进。
    var exportJSONData: Data? {
        var lines = ["["]
        for (index, item) in exportItems.enumerated() {
            let objectComma = index < exportItems.count - 1 ? "," : ""
            lines.append("  {")
            lines.append("    \"id\": \(Self.jsonString(item.id)),")
            lines.append("    \"name\": \(Self.jsonString(item.name)),")
            lines.append("    \"elite\": \(item.elite),")
            lines.append("    \"level\": \(item.level),")
            lines.append("    \"own\": \(item.own ? "true" : "false"),")
            lines.append("    \"potential\": \(item.potential),")
            lines.append("    \"rarity\": \(item.rarity)")
            lines.append("  }" + objectComma)
        }
        lines.append("]")
        return lines.joined(separator: "\n").data(using: .utf8)
    }

    private static func jsonString(_ value: String) -> String {
        var escaped = "\""
        for scalar in value.unicodeScalars {
            switch scalar.value {
            case 0x22: escaped += "\\\"" // "
            case 0x5C: escaped += "\\\\" // 反斜杠
            case 0x08: escaped += "\\b"
            case 0x0C: escaped += "\\f"
            case 0x0A: escaped += "\\n"
            case 0x0D: escaped += "\\r"
            case 0x09: escaped += "\\t"
            case 0x00...0x1F:
                escaped += String(format: "\\u%04X", scalar.value)
            default:
                escaped.unicodeScalars.append(scalar)
            }
        }
        escaped += "\""
        return escaped
    }
}

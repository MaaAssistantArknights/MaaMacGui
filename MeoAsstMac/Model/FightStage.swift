//
//  FightStage.swift
//  MAA
//
//  Created by hguandl on 2026/9/11.
//

import Foundation

struct FightStage: Identifiable {
    let code: String
    var id: String { code }

    let name: String?
    let drop: String

    enum OpenType {
        case resourceCollection(weekdays: [Int]?)
        case activity(startTime: Date?, expireTime: Date?)
    }

    let openType: OpenType
}

extension FightStage {
    func isOpen(at date: Date, stageActivity: StageActivityContext) -> Bool {
        switch openType {
        case .activity(let startTime, let expireTime):
            if let startTime, date < startTime {
                return false
            }
            if let expireTime, date > expireTime {
                return false
            }
            return true
        case .resourceCollection(let weekdays):
            return stageActivity.resourceCollectionStageIsOpen(at: date, in: weekdays)
        }
    }
}

extension FightStage {
    static func tips(for date: Date, stageActivity: StageActivityContext) -> [(code: String, drop: String)] {
        supplies.filter { $0.isOpen(at: date, stageActivity: stageActivity) }
            .map { ($0.code, $0.drop) }
            + metaChips.filter { $0.isOpen(at: date, stageActivity: stageActivity) }
            .map { ($0.code, String(localized: $0.drop)) }
    }
}

extension FightStage {
    fileprivate static let supplies: [FightStage] = [
        .init(
            code: "CE-6", name: .init(localized: "龙门币-6/5"),
            drop: .init(localized: "龙门币"),
            openType: .resourceCollection(weekdays: [2, 4, 6, 0])),
        .init(
            code: "AP-5", name: .init(localized: "红票-5"),
            drop: .init(localized: "红票"),
            openType: .resourceCollection(weekdays: [1, 4, 6, 0])),
        .init(
            code: "CA-5", name: .init(localized: "技能-5"),
            drop: .init(localized: "技能"),
            openType: .resourceCollection(weekdays: [2, 3, 5, 0])),
        .init(
            code: "LS-6", name: .init(localized: "经验-6/5"),
            drop: .init(localized: "经验"),
            openType: .resourceCollection(weekdays: nil)),
        .init(
            code: "SK-5", name: .init(localized: "碳-5"),
            drop: .init(localized: "碳"),
            openType: .resourceCollection(weekdays: [1, 3, 5, 6])),
    ]

    fileprivate static let metaChips: [MetaChip] = [
        .init(baseCode: "PR-A", names: ["奶/盾芯片", "奶/盾芯片组"], drop: "奶&盾芯片", weekdays: [1, 4, 5, 0]),
        .init(baseCode: "PR-B", names: ["术/狙芯片", "术/狙芯片组"], drop: "术&狙芯片", weekdays: [1, 2, 5, 6]),
        .init(baseCode: "PR-C", names: ["先/辅芯片", "先/辅芯片组"], drop: "先&辅芯片", weekdays: [3, 4, 6, 0]),
        .init(baseCode: "PR-D", names: ["近/特芯片", "近/特芯片组"], drop: "近&特芯片", weekdays: [2, 3, 6, 0]),
    ]

    fileprivate static let chips: [FightStage] = metaChips.flatMap { meta in
        meta.names.enumerated().map { (index, name) in
            .init(
                code: "\(meta.baseCode)-\(index + 1)", name: .init(localized: name),
                drop: .init(localized: meta.drop),
                openType: .resourceCollection(weekdays: meta.weekdays))
        }
    }
}

private struct MetaChip {
    let baseCode: String
    let names: [LocalizedStringResource]
    let drop: LocalizedStringResource
    let weekdays: [Int]
}

extension MetaChip {
    var code: String {
        let codes = (1...names.count).map(String.init).joined(separator: "/")
        return "\(baseCode)-\(codes)"
    }

    func isOpen(at date: Date, stageActivity: StageActivityContext) -> Bool {
        stageActivity.resourceCollectionStageIsOpen(at: date, in: weekdays)
    }
}

//
//  MallConfiguration.swift
//  MAA
//
//  Created by hguandl on 16/4/2023.
//

import Foundation
import JBird

struct MallConfiguration: MAATaskConfiguration {
    var type: MAATaskType { .Mall }

    var shopping: Bool
    var buy_first: [String]
    var blacklist: [String]
    var force_shopping_if_credit_full: Bool
    var only_buy_discount: Bool
    var reserve_max_credit: Bool

    var visitFriends: Bool
    var creditFight: Bool
    var formationIndex: Int
    var clientChannel: MAAClientChannel

    var creditFightDate: Date
    var friendVisitDate: Date

    /// startTasks 注入的同批判定基准时刻：参数闸门与同批去重预标记共用同一读数，
    /// 消除注入到 append 之间（ensureHandle 装载框架可达秒级）跨 04:00 导致的同批双放行。
    /// 仅存活于单次批次内，不参与编解码；未注入时为 nil，闸门退化为读当前时钟。
    var batchSnapshotDate: Date? = nil

    // CodingKeys 显式排除 batchSnapshotDate，保持持久化结构不变。
    enum CodingKeys: String, CodingKey {
        case shopping
        case buy_first
        case blacklist
        case force_shopping_if_credit_full
        case only_buy_discount
        case reserve_max_credit
        case visitFriends
        case creditFight
        case formationIndex
        case clientChannel
        case creditFightDate
        case friendVisitDate
    }

    var title: String {
        type.description
    }

    var subtitle: String {
        if shopping {
            return String(localized: "购物")
        } else {
            return String(localized: "不购物")
        }
    }

    var summary: String {
        buy_first.joined(separator: ";")
    }

    var projectedTask: MAATask {
        .mall(self)
    }

    @JSON.Builder var params: JSON {
        // 闸门消费 startTasks 物化的同批快照时刻（与去重预标记同源），“判定”与“消费”
        // 共用一次时钟读数；未经批次注入时退化为读当前时钟。
        let now = batchSnapshotDate ?? Date.now
        let calendar = clientChannel.calendar
        let shouldCreditFight = creditFight && !calendar.isDate(creditFightDate, inSameDayAs: now)
        let shouldVisitFriends = visitFriends && !calendar.isDate(friendVisitDate, inSameDayAs: now)

        "visit_friends" => shouldVisitFriends
        "shopping" => shopping
        "buy_first" => buy_first
        "blacklist" => blacklist
        "force_shopping_if_credit_full" => force_shopping_if_credit_full
        "only_buy_discount" => only_buy_discount
        "reserve_max_credit" => reserve_max_credit
        "credit_fight" => shouldCreditFight
        if shouldCreditFight {
            "formation_index" => formationIndex
        }
    }
}

extension MallConfiguration {
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.shopping = try container.decodeIfPresent(Bool.self, forKey: .shopping) ?? true
        self.buy_first = try container.decodeIfPresent([String].self, forKey: .buy_first) ?? ["招聘许可", "龙门币"]
        self.blacklist = try container.decodeIfPresent([String].self, forKey: .blacklist) ?? ["加急许可", "家具零件"]
        self.force_shopping_if_credit_full =
            try container.decodeIfPresent(Bool.self, forKey: .force_shopping_if_credit_full) ?? true
        self.only_buy_discount = try container.decodeIfPresent(Bool.self, forKey: .only_buy_discount) ?? false
        self.reserve_max_credit = try container.decodeIfPresent(Bool.self, forKey: .reserve_max_credit) ?? false

        self.visitFriends = container[.visitFriends, default: true]
        self.creditFight = container[.creditFight, default: false]
        self.formationIndex = container[.formationIndex, default: 0]
        self.clientChannel = container[.clientChannel, default: .Official]

        self.creditFightDate = container[.creditFightDate, default: .distantPast]
        self.friendVisitDate = container[.friendVisitDate, default: .distantPast]
    }
}

// MARK: - Batch Daily Admission

extension MallConfiguration {
    /// 同一批次多个 Mall 的每日任务准入结果：只有"具备资格但未获得放行"的项携带预标记日期。
    struct BatchDailyAdmission: Equatable {
        var creditFightMarkedDate: Date?
        var friendVisitMarkedDate: Date?
    }

    /// 同一批次可能存在多个 Mall：每种每日任务只放行首个具备资格者（启用、开关开启且当日未完成），
    /// 其余具备资格者返回 snapshotDate 作为预标记日期，写入对应日期字段后参数闸门按同一
    /// snapshotDate 判定即跳过（次日自愈）。不具备资格者不占放行名额、不预标记。
    static func batchDailyAdmissions(
        of entries: [(enabled: Bool, config: MallConfiguration)],
        snapshotDate: Date,
        calendar: HGCalendar
    ) -> [BatchDailyAdmission] {
        var creditFightAdmitted = false
        var friendVisitAdmitted = false

        return entries.map { entry in
            var admission = BatchDailyAdmission(creditFightMarkedDate: nil, friendVisitMarkedDate: nil)

            if entry.enabled, entry.config.creditFight,
                !calendar.isDate(entry.config.creditFightDate, inSameDayAs: snapshotDate)
            {
                if creditFightAdmitted {
                    admission.creditFightMarkedDate = snapshotDate
                } else {
                    creditFightAdmitted = true
                }
            }

            if entry.enabled, entry.config.visitFriends,
                !calendar.isDate(entry.config.friendVisitDate, inSameDayAs: snapshotDate)
            {
                if friendVisitAdmitted {
                    admission.friendVisitMarkedDate = snapshotDate
                } else {
                    friendVisitAdmitted = true
                }
            }

            return admission
        }
    }

    /// 消息处理可能滞后于实际完成时刻：完成于 03:59:59.x、消息于 04:00:00.y 处理时，
    /// 直接回写处理时刻会把日期记到新游戏日，导致当日信用战/访问被误跳过。
    /// 此时保守回写轮始时刻所在的游戏日：宁可下轮重复提交（core 侧幂等消化），不可漏掉当日任务。
    /// 无轮始锚点或与处理时刻同处一个游戏日时，仍回写处理时刻。
    static func dailyWriteBackDate(now: Date, roundStart: Date?, calendar: HGCalendar) -> Date {
        guard let roundStart, !calendar.isDate(now, inSameDayAs: roundStart) else {
            return now
        }
        return roundStart
    }
}
